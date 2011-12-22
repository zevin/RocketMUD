#
# RocketMUD was written by Jon Lambert, 2006.
# It is based on SocketMUD(tm) written by Brian Graversen.
# This code is released to the public domain.
#
#
# This file contains all sorts of utility functions used
# all sorts of places in the code.
#

#
# Check to see if a given name is
# legal, returning FALSE if it
# fails our high standards...
#
def check_name name
  return false if (name.size < 3 || name.size > 12)
  if name =~ /^[[:alpha:]]+$/
    return true
  else
    return false
  end
end

# Communication Ranges
# :comm_local           =  0  # same room only
# :comm_log             = 10  # admins only
def communicate dMob, txt, range
  buf = ""
  msg = ""

  case range
  when :comm_local   # everyone is in the same room for now...
    msg = sprintf "%s says '%s'.\r\n", dMob.name, txt
    buf = sprintf "You say '%s'.\r\n", txt
    dMob.text_to_mobile buf
    $dmobile_list.each do |xMob|
      next if xMob == dMob
      xMob.text_to_mobile msg
    end
  when :comm_log
    msg = sprintf "[LOG: %s]\r\n", txt
    $dmobile_list.each do |xMob|
      next if !xMob.is_admin?
      xMob.text_to_mobile msg
    end
  else
    bug "Communicate: Bad Range %d.", range
    return;
  end
end

#
# Loading of help files, areas, etc, at boot time.
#
def load_muddata
  load_helps
end

def get_time
  Time.now.ctime.slice(4..15)
end

def check_reconnect player
  $dmobile_list.each do |dMob|
    if dMob.name.casecmp(player) == 0
      dMob.socket.close_socket true if dMob.socket
      return dMob
    end
  end
  nil
end

#
# Checks if aStr is a prefix of bStr.
#
def is_prefix astr, bstr
  return false if astr.nil? || bstr.nil? || astr.empty? || bstr.empty?
  astr == bstr.slice(0...astr.size)
end

def one_arg! fstr, bstr
  bstr.slice! 0..-1
  bstr << (fstr.slice!(/\w+/) || '')
  fstr.lstrip!
end

#!ruby
#
# Rocketmud
#
# This source code copyright (C) 2006 by Jon A. Lambert
# All rights reserved.
#
# Released under the terms of the RocketMUD Public License
# See LICENSE file for additional information.
#

#
# This file handles input/output to files (including log)
#

#
# Nifty little extendable logfunction,
# if it wasn't for Erwins social editor,
# I would never have known about the
# va_ functions.
#
def log_string(*args)
  File.open(sprintf("log/%6.6s.log", get_time), "a") do |f|
    f.printf "%s: %s\n", get_time, sprintf(*args)
  end
  communicate nil, sprintf(*args), :comm_log
rescue
  puts $!.to_s, $@
  communicate nil, "log: cannot open logfile", :comm_log
end

#
# Nifty little extendable bugfunction,
# if it wasn't for Erwins social editor,
# I would never have known about the
# va_ functions.
#
def bug(*args)
  File.open("log/bugs.txt", "a") do |f|
    f.printf "%s: %s\n", get_time, sprintf(*args)
  end
  communicate nil, sprintf(*args), :comm_log
rescue
  puts $!.to_s, $@
  communicate nil, "log: cannot open bugfile", :comm_log
end

#
# This function will return the time of
# the last modification made to a file.
#
def last_modified file
  return File.stat(file).mtime.to_i
rescue
  return 0
end

def read_help_entry helpfile
  File.open(sprintf("%s", helpfile), "r") do |f|
    # just to have something to work with
    c = f.getc
    entry = ""

    # read the file in the buffer
    while !c.nil?
      if c == ?\n
        entry << "\r\n"
      elsif c == ?\r
        c = f.getc
        next
      else
        entry << c.chr
      end
      if entry.size > MAX_BUFFER
        bug "Read_help_entry: String to long."
        abort
      end
      c = f.getc
    end

    # return a pointer to the static buffer
    return entry
  end
rescue
  log_string $!.to_s
  # if there is no help file, return NULL
  nil
end

def save_player dMob
  return if dMob.nil?
  File.open(sprintf("players/%s.yml", dMob.name.downcase.capitalize), "w") do |f|
    YAML::dump dMob,f
  end
rescue
  log_string "Unable to write to %s's pfile", dMob.name
  log_string $!.to_s
end

def load_player player
  dMob = YAML::load_file sprintf("players/%s.yml", player.downcase.capitalize)
  dMob.initialize
  return dMob
rescue
  log_string "Load_player: File open error for %s's pfile.", player
  log_string $!.to_s
  return nil
end

