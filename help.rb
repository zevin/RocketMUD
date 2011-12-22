#
# RocketMUD was written by Jon Lambert, 2006.
# It is based on SocketMUD(tm) written by Brian Graversen.
# This code is released to the public domain.
#
#
# This file contains the dynamic help system.
# If you wish to update a help file, simply edit
# the entry in ../help/ and the mud will load the
# new version next time someone tries to access
# that help file.
#

#
# Check_help()
#
# This function first sees if there is a valid
# help file in the help_list, should there be
# no helpfile in the help_list, it will check
# the ../help/ directory for a suitable helpfile
# entry. Even if it finds the helpfile in the
# help_list, it will still check the ../help/
# directory, and should the file be newer than
# the currently loaded helpfile, it will reload
# the helpfile.
def check_help dMob, helpfile
  pHelp = nil
  entry = nil
  hFile = helpfile.upcase

  $help_list.each do |p|
    if is_prefix hFile, p.keyword
      pHelp = p
      break
    end
  end

  # If there is an updated version we load it
  if pHelp
    if last_modified(sprintf("help/%s", hFile)) > pHelp.load_time
      pHelp.text = read_help_entry "help/#{hFile}"
    end
  else # is there a version at all ??
    entry = read_help_entry "help/#{hFile}"
    if entry == nil
      return false
    else
      pHelp = Help.new hFile, entry
      $help_list << pHelp
    end
  end

  dMob.text_to_mobile sprintf("=== %s ===\r\n%s", pHelp.keyword, pHelp.text)

  return true
end

#
# Loads all the helpfiles found in ../help/
#
def load_helps
  log_string "Load_helps: getting all help files."

  Dir.entries("help").each do |entry|
    next if File.stat("help/#{entry}").directory?
    s = read_help_entry "help/#{entry}"

    if s.nil?
      bug "load_helps: Helpfile %s does not exist.", entry
      next
    end

    new_help = Help.new entry, s
    $help_list << new_help

    if "GREETING".casecmp(new_help.keyword) == 0
      $greeting = new_help.text
    elsif "MOTD".casecmp(new_help.keyword) == 0
      $motd = new_help.text
    end
  end
end

if __FILE__ == $0
  load_helps
  puts $motd
  puts $greeting
  pp $help_list
end
