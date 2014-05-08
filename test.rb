#encoding: utf-8
require './led.rb'
WRITE=true
art =  Art.new 128, 16, 1
art.rmagick_text_pos 0, 0, "لوحة المفاتيح".encode("utf-16").reverse.encode("utf-8")
art.rmagick_write
