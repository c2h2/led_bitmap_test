#encoding: utf-8
require 'socket'
require 'RMagick'
require 'timeout'

DUAL = 2
DRYRUN||=false
DEBUG||=false
WRITE||=false
MULTITHREADING||=true
LED_THREAD_DELAY||=50
TCP_TIMEOUT||=10
DEFAULT_FONT||="/usr/share/fonts/truetype/unifont/unifont.ttf"

BUZZ_IP="192.168.0.51"
BUZZ_PORT=5088

class DoorHard
  def self.door_open
    s=UDPSocket.new
    s.send("OPEN", 0, BUZZ_IP, BUZZ_PORT)
  end
  def self.door_close
    s=UDPSocket.new
    s.send("CLOS", 0, BUZZ_IP, BUZZ_PORT)
  end
end

class LedLogger
  def self.log str
    puts str if DEBUG
  end
end

class LedInit
  def self.boardcast data
    u=UDPSocket.new
    u.setsockopt(Socket::SOL_SOCKET, Socket::SO_BROADCAST, true)
    LedLogger.log data
    u.send(data.to_bin, 0, '255.255.255.255', 9999)
    u.close
  end
  
  def self.set_mac mac= "aabbccddee01"
    boardcast "010102020303e806#{mac}dcaa"
  end

  def self.set_ip ip="192.168.0.200", netmask="255.255.255.0", gateway="192.168.0.1", port=5005
    p = Proc.new{|add| add.split(".").map{|b| b.to_i.to_padded_hex(2)} * ""}
    ip_hex = p.call(ip)
    netmask_hex = p.call(netmask)
    gateway_hex = p.call(gateway)
    port_hex = (port%256).to_padded_hex(2) + (port/256).to_padded_hex(2)
    boardcast "010102020303e70e#{ip_hex}#{netmask_hex}#{gateway_hex}#{port_hex}5eaa"
  end
end

class LedHard
  attr_reader :led_h, :led_v
  def initialize led_ip, led_port, width, height, dual_color = DUAL
    @led_ip      = led_ip
    @led_port    = led_port
    @led_h       = width
    @led_v       = height
    @data_size   = width * height * dual_color
    @socket_closed = true #enabling reuse of socket
  end

  def tcp_close
    @socket.close unless DRYRUN
    @socket_closed = true
  end

  def tcp_send string, do_recv=true
    ret = nil
    tcp_init	
    @socket.write string.to_bin unless DRYRUN
    LedLogger.log string
    ret = @socket.recv(1024).to_hex if (do_recv and !DRYRUN)
    LedLogger.log ret
    ret
  end

  def tcp_send_file fn
    tcp_send File.open(fn, "r").read unless DRYRUN
  end

  private

  def tcp_init
    if @socket_closed
      @socket = TCPSocket.open( @led_ip , @led_port ) unless DRYRUN
      @socket_closed = false
    end
  end
end

class LedProg
  def initialize # can have many led screens
    @leds = [] 
  end

  def add_led led_hard
    @leds << led_hard
  end

  def ping
    pings = time_sync
  end

  def led_setup params={}
    defaults = {:width=>192, :height=>32, :color=>"02", :scan=>"02", :scan_method=>"10", :data_flow=>"00", :mirror=>"00", :oe_polarity=>"00", :data_polarity=>"00" }
    params = defaults.merge params
    content = params[:width].to_padded_hex + params[:height].to_padded_hex + params[:color] + params[:scan] + "00ff" + params[:scan_method] + params[:data_flow] +params[:mirror] + params[:oe_polarity] + params[:data_polarity]
    led_send "01c108#{content}4eaa", "c1"
  end

  def timed_power_control h_up, m_up, h_down, m_down
    led_send "01c301"+"#{m_up.to_bcd}#{h_up.to_bcd}#{m_down.to_bcd}#{h_down.to_bcd}"+"ffffffffffffffff72aa", "c3"
  end

  def clear_timed_power_control
    led_send "01c3ffffffffffffffffffffffffffb7aa", "c3"
  end
  
  def time_sync t=(Time.now+1) #assume network delay and processing = 1 second
    #to update time do: sudo date -s "2011-06-08 12:34:56"
    time_code = "#{t.sec.to_bcd}#{t.min.to_bcd}#{t.hour.to_bcd}#{t.day.to_bcd}#{t.month.to_bcd}#{(t.wday == 0 ? 7 : t.wday).to_bcd}#{(t.year-2000).to_bcd}"
    led_send "01cd07#{time_code}41aa", "cd"
  end

  def power_on
    led_send "01c40100b6aa", "c4"
  end

  def power_off
    led_send "01c401ffb6aa", "c4"
  end

  # only 192 * 32 screen
  def program_one_zone pages, text, width=192, height=32, params={}
    led_send (header_tag(width, height) + text_bitmap(width, height, 0, 0 ,pages, text, params) + tail_tag)
  end
 
  #empty dyn_zone, text zone, and dynamic_zone 
  def program_three_zone pages, text, params={}
    width = 160
    height = 12
    header = "01d1010000012c03060000000c000c0014101001020000000000"+ (width/16).to_padded_hex + height.to_padded_hex + "1010" #000a, 000c is the w and h 
    
    content = header + text_bitmap(width, height, 0, 0, pages, text, params) + File.open(File.dirname(__FILE__) + "/time_fonts_bytes.txt", "r").read.strip + tail_tag
    led_send content
  end

  def program_progress_bar params={}
    defaults = {:color => "green", :dyn => false, :top=>3 , :direction=>true, :door_side=>true}
    params = defaults.merge params

    content = "01d1010000012c010600000000000600101010010211061301120702f4aa"
    led_send content
  end

  def program_static_progress_bar now, total, params={}
    width = 96
    height = 16
    led_send( header_tag(width, height) + dots_bitmap(width, height, now, total, params) + tail_tag )
  end

  def send_dynamic_progress_bar now, total, params={}
    defaults = {:color => "green", :dyn => true, :top=>3 , :direction=>true, :door_side=>true, :pages=>8, :display_other_routes=>true}
    params = defaults.merge params
    width = 96
    height = 16
    t_door=Thread.new{
    if params[:in_at_out] == "in"
  
    elsif params[:in_at_out] == "at"
      DoorHard.door_open
    elsif params[:in_at_out] == "out"
      DoorHard.door_close
    end
    }
    header = get_dynamic_zone_header(0, 0, width, height, params[:pages])
    finish = "a1aa"
    content = header + dots_bitmap(width, height, now, total, params) + finish
    led_send content, "d2", false
    t_door.join
  end

  def send_dynamic_zone x, y, width, height, pages, text, params={}
    defaults = {:pointsize=> 16, :color => "red", :dyn=>true, :prog_enter_method => "10", :prog_speed=>"0f", :prog_pause_sec => "0a"}
    params = defaults.merge params
    finish = "a1aa"
    t0 = Time.now
    pages =  Art.rmagick_num_screens text, width, params
    header = get_dynamic_zone_header(x, y, width, height, pages)
    puts "PAGES = #{pages}"
    params[:auto_center] = true if pages == 1
    bitmaps = text_bitmap(width, height, 0, 0, pages, text, params)
    content = header + bitmaps + finish
    t1 = Time.now
    led_send content, "d2", false
    return [t1 - t0 , Time.now - t0] # returns [prepare_time, total_time]
  end
  
  def get_rs485_data text, params={}
   
    defaults = {:dyn=>true, :prog_disp_method =>"12", :width=>160, :height=>16, :color => "green", :pointsize=>16, :prog_speed=>"01", :prog_pause_sec => "02", :prog_enter_method=>"12"}
    params = defaults.merge params
    pages = Art.rmagick_num_screens text, params[:width], params
    if pages==1
      params[:auto_center] = true 
      params[:prog_disp_method] = "01"
    end
    puts "PAGES = #{pages}"
    tail = "AA"
    head = "0#{params[:sn]}E000000296"
    data_head = "00010000000000001400100808"       
    data_img = text_bitmap_c2(params[:width], params[:height], 0, 0, pages, text, params)
    data = data_head + data_img 
    final = head + data + data.checksum(8) + tail
  end

  private
  def header_tag width, height
   "01d1010000012c010000000000#{(width/16).to_padded_hex}#{height.to_padded_hex}1010" 
  end
  
  def tail_tag 
    "110528061707063caa"
  end

  def get_dynamic_zone_header(x, y, width, height, pages)
    zone_num = "00"
    zone_type = "06"
    zone_x_crood = x.to_padded_hex
    zone_y_crood = y.to_padded_hex
    zone_width   = (width/16).to_padded_hex
    zone_height  = height.to_padded_hex
    zone_byte_av = "1010"
    zone_pages = pages.to_padded_hex(2)   #update_pages = pages.to_padded_hex(2)

    header = zone_num + zone_type + zone_x_crood + zone_y_crood + zone_width + zone_height + zone_byte_av + zone_pages
  end

  def art2bitmap art, params={}
    art.rmagick2array
    bitmap_strings = art.get_screens_strings

    style = params[:prog_enter_method] + params[:prog_exit_method] + params[:prog_speed] + params[:prog_pause_sec]
    bitmap = bitmap_strings.length.to_padded_hex(2)
    bitmap_strings.each_with_index do |str, index|
      bitmap = bitmap + index.to_padded_hex(2) if params[:dyn]
      bitmap = bitmap + style + str
    end
    bitmap
  end

  def art2bitmap_c2 art, params={}
    art.rmagick2array
    bitmap_strings = art.get_screens_strings
    reserve = "00"
    continue_wh = "0000"
    style = params[:prog_disp_method] *3 + params[:prog_pause_sec] + continue_wh
    bitmap = bitmap_strings.length.to_padded_hex(2) * 2
    bitmap_strings.each_with_index do |str, index|
      bitmap = bitmap + index.to_padded_hex(2) if params[:dyn]
      bitmap = bitmap + style + str
    end
    bitmap


  end

  def dots_bitmap width, height, now, total, params={}
    defaults = {:visited_col => "red", :now_col=>"green", :next_col1=>"green", :next_col2=>"orange", :door_col=>"green", :unvisted=>"black", :direction=>true, :correct_open_side=>true, :dyn => false, :prog_enter_method=>"01", :prog_exit_method=>"01", :prog_speed=>"02", :prog_pause_sec => "01", :x_padding=>3, :y_top=>3, :pages=>6, :display_next=>true, :door_side=>true, :display_running=>true, :in_at_out=>"at", :display_other_routes=>false}
    params = defaults.merge params

    now = 0 if now < 0
    now = now + 1 unless params[:in_at_out] == "in" # into a station -> station index -1

    x_padding = params[:x_padding]
    x_start = (((width - x_padding * 2) % total)/2).floor + x_padding - 1
    x_diff = ((width - x_padding * 2) / (total-1)).floor
    xs=[]
    total.times{|t| xs[t] = x_start + x_diff * t}

    art= Art.new width, height, params[:pages]

    if params[:display_running]
      if params[:direction]
        params[:pages].times{|i| art.rmagick_line( xs[0] + i*width, params[:y_top], xs[now-1] + i * width, params[:y_top], params[:visited_col])}
      else
        params[:pages].times{|i| art.rmagick_line( width - xs[0] -2 + i*width, params[:y_top], width - xs[now-1] - 2 + i * width, params[:y_top], params[:visited_col])}
      end
    else
      now.times do |i|
        x0 = params[:direction] ? xs[i] : width - xs[i] - 2
        params[:pages].times{|i| art.rmagick_col(x0 + i * width , params[:y_top], params[:visited_col]) } #screen x
      end
    end
    
    if params[:in_at_out] == "at"
      x0 = params[:direction] ? xs[now - 1] : width - xs[now-1] - 2
      params[:display_next] = false
      params[:pages].times do |i| 
        art.rmagick_col(x0 + i * width , params[:y_top], params[:next_col1])  if i%2==0
        art.rmagick_col(x0 + i * width , params[:y_top], params[:next_col2])  if i%2==1
      end
    end

    if params[:display_next] and (now != total )
      x0 = params[:direction] ? xs[now] : width - xs[now] - 2
      params[:pages].times do |i| 
        art.rmagick_col(x0 + i * width , params[:y_top], params[:next_col1])  if i%2==0
        art.rmagick_col(x0 + i * width , params[:y_top], params[:next_col2])  if i%2==1
      end

      if params[:display_running]
        block = (x_diff/params[:pages]).ceil
        xr0s =[]
        xr1s =[]
        x0 = params[:direction]? xs[now-1] : width - xs[now-1] -2
        params[:pages].times do |i| 
          xr0s[i] = (params[:direction]? x0 + i* block + 1: x0 - i * block - 1) + i * width
          xr1s[i] = params[:direction]? xr0s[i] + block : xr0s[i] - block
        end
        
        params[:pages].times do |i|
          art.rmagick_line(xr0s[i], params[:y_top], xr1s[i], params[:y_top], params[:visited_col])
        end
      end
    end

    #the X cross
    if params[:display_other_routes]
      x0 = 28
      x1 = 29
      x2 = 30 
      x3 = 31 
      x4 = 33 
      x5 = 34 
      x6 = 35 
      x7 = 36 
      
      y0 = 1
      y1 = 2
      y2 = 4
      y3 = 5
      
      params[:pages].times do |i| 
        #line 1
        color = params[:door_col]
        art.rmagick_col(x2 + i*width, y0, color)
        art.rmagick_col(x3 + i*width, y1, color)
        art.rmagick_col(x4 + i*width, y2, color)
        art.rmagick_col(x5 + i*width, y3, color)
        art.rmagick_col(x6 + i*width, y3, color)
        art.rmagick_col(x7 + i*width, y3, color)
        #line 2 
        color = params[:next_col2]
        art.rmagick_col(x5 + i*width, y0, color)
        art.rmagick_col(x4 + i*width, y1, color)
        art.rmagick_col(x3 + i*width, y2, color)
        art.rmagick_col(x0 + i*width, y3, color)
        art.rmagick_col(x1 + i*width, y3, color)
        art.rmagick_col(x2 + i*width, y3, color)
      end
    end

    if params[:door_side]
      x0 = width - 7
      y0 = height/2  + 1
      x1 = x0 + 1
      x2 = x1 + 1
      y1 = y0 + 1
      y2 = y1 + 1
      
      params[:pages].times do |i| 
        art.rmagick_col(x0 + i * width, y0, params[:door_col])
        art.rmagick_col(x1 + i * width, y0, params[:door_col])
        art.rmagick_col(x2 + i * width, y0, params[:door_col])
        art.rmagick_col(x0 + i * width, y1, params[:door_col])
        art.rmagick_col(x1 + i * width, y1, params[:door_col])
        art.rmagick_col(x2 + i * width, y1, params[:door_col])
        art.rmagick_col(x1 + i * width, y2, params[:door_col])
      end
    end

    art.rmagick_write
    art2bitmap art, params
  end
  
  def text_bitmap width, height, x, y, pages, text, params={}
    defaults = {:color => "green", :dyn => false, :prog_enter_method=>"12", :prog_exit_method=>"01", :prog_speed=>"02", :prog_pause_sec => "02"}
    params = defaults.merge params
    art = Art.new width, height, pages
    art.rmagick_text_pos x, y, text, params
    art.rmagick_write
    art2bitmap art, params
  end

  def text_bitmap_c2 width, height, x, y, pages, text, params={}
    defaults = {:color => "green", :dyn => false, :prog_enter_method=>"12", :prog_exit_method=>"01", :prog_speed=>"02", :prog_pause_sec => "02"}
    params = defaults.merge params
    art = Art.new width, height, pages
    art.rmagick_text_pos x, y, text, params
    art.rmagick_write
    art2bitmap_c2 art, params
  end

  def led_send content, op_code="d1", do_recv=true
    rets = [] # each led return values
    frame_header = "a5a5"
    comm_type    = "01"
    screen_num   = "0101"
    color_code   = "02"
    empty        = "00" * 3
    prog_num     = "00"
    
    send_proc = Proc.new do |led|
      hoz_dots  = led.led_h.to_padded_hex
      ver_dots  = led.led_v.to_padded_hex
      handshake = frame_header + comm_type + screen_num + op_code + color_code + hoz_dots + ver_dots +empty + prog_num
      begin
        Timeout::timeout(TCP_TIMEOUT) do
          led.tcp_send(handshake, do_recv) # handshake only
          ret = led.tcp_send(content, true) #actual content seding
          led.tcp_close
        end
      rescue
        LedLogger.log "TIMEOUT(#{TCP_TIMEOUT}) or other errors occured"
        ret = nil
      end
      ret
    end

    tpool = []
    @leds.each_with_index do |led, index|
      if MULTITHREADING
        delay = (@leds.length-index-1) * LED_THREAD_DELAY / 1000.0
        tpool << Thread.new{sleep delay; rets[index] = send_proc.call led}
      else
        rets << send_proc.call(led)
      end
    end
    tpool.each{|t| t.join} if MULTITHREADING
    rets
  end
end

class Art 
  def initialize w, h, num_screens, orient=true #true = horizontal screens
    @w, @h = w, h
    @num_screens  = num_screens
    @orient = orient
    @tw = orient ? w * num_screens : w #total width
    @th = orient ? h : num_screens * h #total heigh
    @data_size =  @th * @tw * DUAL
    @screen = [true] * @data_size 
    rmagick_init
  end
  
  def rmagick_init 
    #@img ||=  Magick::Image.new(@tw, @th){ self.background_color ="black"}
    @img =  Magick::Image.new(@tw, @th){ self.background_color ="black"}
  end

  def rmagick_text_pos x, y, text, params={}
    #can use rmagick width metrics: http://stackoverflow.com/questions/378887/how-do-i-calculate-a-strings-width-in-ruby
  
    return if text.nil? or text.length == 0
    defaults = {:pointsize => 16, :color => "green", :font=>DEFAULT_FONT, :aa => false, :stroke => "transparent", :gravity=>Magick::WestGravity, :auto_center=>false}
    params = defaults.merge params
    params[:gravity] = Magick::CenterGravity if params[:auto_center]
    gc = Magick::Draw.new
    gc.text_antialias = params[:aa]
    LedLogger.log "#{x} #{y} #{text}"
    gc.annotate(@img, 0,0,x,y, text) do
      self.font_weight = Magick::LighterWeight
      self.gravity   = params[:gravity]
      self.font      = params[:font]
      self.pointsize = params[:pointsize]
      self.fill      = params[:color]
      self.stroke    = params[:stroke]
    end
  end

  def self.rmagick_measure_width text, params={}
    defaults = {:pointsize => 12, :color => "green", :font=>DEFAULT_FONT, :aa => false, :stroke => "transparent"}
    params = defaults.merge params
    gc = Magick::Draw.new
    gc.text_antialias = params[:aa]
    gc.font_weight = Magick::LighterWeight
    gc.font=params[:font]
    gc.pointsize=params[:pointsize]
    gc.fill=params[:color]
    gc.stroke=params[:stroke]
    metrics=gc.get_type_metrics(text)
    LedLogger.log "METRICS Sizing: text=#{text}, w=#{metrics.width}px, h=#{metrics.height}px."
    return {:width=>metrics.width, :height=> metrics.height}
  end

  def self.rmagick_num_screens text, width, params={}
    pages = ( rmagick_measure_width(text, params)[:width].to_f/ width.to_f).ceil
    pages
  end

  def rmagick_write 
    begin
      @img.write('./led.png') if WRITE
    rescue

    end
  end

  def rmagick_col x, y, color
    gc = Magick::Draw.new
    gc.fill color
    gc.point x, y
    gc.draw(@img) do
      self.fill color
      self.point x, y
    end
  end

  def rmagick_line x0, y0, x1, y1, color
    gc = Magick::Draw.new
    gc.fill color
    gc.line(x0, y0, x1, y1)
    gc.draw(@img) do
      self.fill color
      self.line x0, y0, x1, y1
    end
  end

  def rmagick2array
    @th.times do |y|
      @tw.times do |x|
        pix = @img.pixel_color(x,y)
        #set_color(x,y, !(pix.green > 2 ** 12), !(pix.red > 2 ** 12)), antialising mode
        set_color(x,y, !(pix.green > 0), !(pix.red > 0))
      end
    end
  end

  def set_col x, y, color
    case color
    when "green"
      set_color x, y, true, false
    when "red"
      set_color x, y, false, true
    when "orange"
      set_color x, y, true, true
    else 
      set_color x, y, false, false
    end
  end

  def set_color x, y, color1, color2
    indexC1 = @tw * y * DUAL + (x / 8).floor * DUAL * 8 + x % 8
    indexC2 = indexC1 + 8
    @screen[indexC1] = color1
    @screen[indexC2] = color2
  end

  def get_screens_strings
    screens = []
    @num_screens.times do |n|
      per_screen = ""
      bytes = @data_size / 8 / @num_screens
      line_bytes = @tw * DUAL / 8
      single_line_bytes = line_bytes / @num_screens
      screen_bytes = @w * @h * DUAL / 8
      bytes.times do |b|
        if @orient
          h_off = n * @w * DUAL / 8
          v_off = (b / single_line_bytes).floor * line_bytes #(@tw * DUAL * 8)
          now = b % single_line_bytes
          start = h_off + v_off + now
          LedLogger.log "#{bytes}, #{line_bytes}, #{b}, #{h_off}, #{v_off}, #{now}, #{start}"
          per_screen<< (@screen[(start*8)..((start+1)*8-1)]).to_bin
        else
          screen_offset = n * screen_bytes 
          per_screen<< (@screen[(start*8)..((start+1)*8-1)]).to_bin
        end
      end
      LedLogger.log per_screen.length
      LedLogger.log per_screen.to_hex.length

      screens << per_screen.to_hex
    end
    screens
  end
end

class Fixnum
  def to_padded_hex total_length=4
    s=self.to_s(16)    
    s.length >= total_length ? s : "0" * (total_length - s.length) + s
  end

  def to_bcd #only need with yangbang
    self >= 10 ? self.to_s : "0" + self.to_s
  end
end

class Array
  def to_bin #might need optimize performance
    str = "0b"
    self.each{|b| str << (b ? "1" : "0")}
    (eval str).chr
  end
end

class String
  def real_text_width
           
  end

  def visualize
    bytes = []
    len = self.length
    return nil unless len.even?
    (len/2).times{|i| bytes << self[(i*2)..(i*2+1)]}
    bytes
  end

  def to_bin
    [self].pack("H*")
  end

  def to_hex
    str=""
    self.each_byte{|b| str << b.to_s(16).add_zero }
    str
  end

  def add_zero
    self.length == 1 ? "0" + self : self
  end

  def checksum length=4
    sum = 0
    self.to_bin.each_byte do |b|
      sum += b
    end
    (sum % (16 ** length)).to_padded_hex(length)
  end
end
