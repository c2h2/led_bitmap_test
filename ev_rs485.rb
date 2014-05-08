#!/usr/local/rvm/rubies/ruby-1.9.2-p290/bin/ruby
# encoding: utf-8
require 'eventmachine'
require 'evma_httpserver'
require 'yaml' # use this because this handles text coding
require 'uri'
require File.expand_path("../led.rb", __FILE__)
require File.expand_path("../serialport.rb", __FILE__)


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



$job_que = []
puts "Clearing LED SCREENS"


RS485.new(1)
