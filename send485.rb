require 'serialport'
require './led.rb'
require 'RMagick'


def pango_create msg
  `pango-view --text #{msg} --output text.png --background=black --foreground=white --font="/usr/share/fonts/truetype/unifont/unifont.ttf 16" --pixels --margin=0 `
end

img = (Magick::Image.read "./text.png").first
width = img.columns
height = img.rows

blocks = (width / 8.0).ceil

puts "blocks = #{blocks}, width= #{width}, height = #{height}" 

cnt = 0 
data=""

#force 1 screen
blocks= 16 


blocks.times do |b|
  16.times do |y|
    byte_color = 0
    8.times do |x|
      if img.pixel_color(x+ b*8 ,y).green> 44440
        g=1
      else
        g=0
      end
      byte_color += 2 ** x * g
#      puts "#{b} #{x} #{y} #{g}"
    end
    data = data + byte_color.to_padded_hex(2)
  end

end
puts data


def recreate_dot_map data
  screen = Array.new(16)
  16.times do |i|
    screen[i]=Array.new(128)
  end 
  blocks = data.length / 2 / 16 
  puts blocks
  blocks.times do |blk|
    16.times do |j|
      idx = blk* 32 + j * 2
      d=data[idx, 2].hex
      8.times do |k|
        screen[j][blk*8+k]= (d & (1 << k) >0 )? "*":" "
      end
    end
  end


  16.times do |i|
    puts screen[i] * ""
  end
      
end

DEV="/dev/ttyS0"
BAUD=9600

trap("INT"){exit 0}
trap("TERM"){exit 0}



class RS485
  def initialize screen_num
    @dev = DEV
    @baud = BAUD
    @sn = screen_num
  end

  def init
    RS485.send_header_command "0#{@sn}fdfd"
    head = "0#{@sn}FD00000021"
    data = "010002007F12022713022700000000235959010600000000001400100808000102"
    tail = "AA"
    content = head + data + data.checksum(8) + tail
    puts content
    sleep MSG_SLEEP_TIME_SHORT
    RS485.rs485_send content
    puts "INIT Completed."
    sleep MSG_SLEEP_TIME_LONG

  end

  def send_dyn msg
    puts "msg:#{msg}"
    wtf = $led.get_rs485_data(URI.decode(msg), {:sn=> @sn, :color => "orange", :pointsize=>16})
    # puts wtf
    RS485.send_header_command "0#{@sn}fde0"
    sleep MSG_SLEEP_TIME_SHORT
    RS485.rs485_send wtf
    sleep MSG_SLEEP_TIME_LONG
    wtf
  end

  def send_static msg

  end

  def empty_dyn


  end

  def self.send_header_command cmd = "0#{@sn}fdfd"
    @sp = SerialPort.open(DEV, BAUD, 8, 1,  SerialPort::ODD)
    @sp.write cmd.to_bin
    @sp.close
  end

  def self.rs485_send(msg, parmas={})
    @sp = SerialPort.open(DEV, BAUD, 8, 1,  SerialPort::EVEN)
    @sp.write msg.to_bin
    puts msg.length
    @sp.close
  end


end



puts "sending data to led screen(s)."
pango_create ARGV[0]
recreate_dot_map data

#rs485=RS485.new(1)
RS485.rs485_send(("A5 00 00 15 10 01 00 02" + data + data + "00 00 5A ").gsub(/\s+/, ""))

=begin
RS485.rs485_send("A5 00 00 15 01 01 00 02 
0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 
F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0
0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 
F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0
0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 
F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0
0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 0F 
F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0
00 00 5A ".gsub(/\s+/, ""))
=end
