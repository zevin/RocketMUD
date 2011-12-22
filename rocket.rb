#!ruby
#
# RocketMUD was written by Jon Lambert, 2006.
# It is based on SocketMUD(tm) written by Brian Graversen.
# This code is released to the public domain.
#
#
require 'socket'
require 'fcntl'
require 'yaml'
require 'singleton'
require 'pp'

require 'constants'


##############################
# End of standard definitons #
##############################


#############################
# New structures            #
#############################

# the actual structures

class Help
  attr_accessor :load_time, :keyword, :text

  def initialize k, t
    @load_time = Time.now.to_i
    @keyword = k
    @text = t
  end
end

class Command
  attr_accessor :cmd_name, :cmd_funct, :level

  def initialize n, f, l
    @cmd_name = n
    @cmd_funct = f
    @level = l
  end
end

#############################
# End of new structures     #
#############################

####################
# Global Variables #
####################

$dsock_list = []         # the linked list of active sockets
$dmobile_list = []       # the mobile list of active mobiles
$shut_down = false       # used for shutdown
$current_time = Time.now # let's cut down on calls to time()
$fSet = []             # the socket list for polling

$help_list = []        # the linked list of help files
$tabCmd = []           # the command table
$greeting = ""         # the welcome greeting
$motd = ""             # the MOTD help file

# the color table...
$ansi_table = [
  [ ?d,  "30",  false ],
  [ ?D,  "30",  true ],
  [ ?r,  "31",  false ],
  [ ?R,  "31",  true ],
  [ ?g,  "32",  false ],
  [ ?G,  "32",  true ],
  [ ?y,  "33",  false ],
  [ ?Y,  "33",  true ],
  [ ?b,  "34",  false ],
  [ ?B,  "34",  true ],
  [ ?p,  "35",  false ],
  [ ?P,  "35",  true ],
  [ ?c,  "36",  false ],
  [ ?C,  "36",  true ],
  [ ?w,  "37",  false ],
  [ ?W,  "37",  true ]
]


#
# The command table, very simple, but easy to extend.
#
$tabCmd = [
 # command          function        Req. Level
 # ---------------------------------------------
  Command.new("commands",  :cmd_commands, LEVEL_GUEST),
  Command.new("help",      :cmd_help,     LEVEL_GUEST),
  Command.new("linkdead",  :cmd_linkdead, LEVEL_ADMIN),
  Command.new("say",       :cmd_say,      LEVEL_GUEST),
  Command.new("save",      :cmd_save,     LEVEL_GUEST),
  Command.new("shutdown",  :cmd_shutdown, LEVEL_GOD),
  Command.new("quit",      :cmd_quit,     LEVEL_GUEST),
  Command.new("who",       :cmd_who,      LEVEL_GUEST)
]

###########################
# End of Global Variables #
###########################

require 'utils'
#require 'help'
#require 'event'
#require 'sockdesc'
#require 'mobile'

def load_control
  loaded = false
  Dir.entries(".").each do |entry|
   begin
    next if entry =~ /rocket|constants/ || entry !~ /\.rb/
    if last_modified(entry) > $load_time.to_i
      Kernel::load(entry)
      log_string "Loaded #{entry}"
      loaded = true
    end
   rescue
    log_string "Unable to load #{entry}"
    log_string $!.to_s
   end
  end
  if loaded
    $load_time = Time.now
  end
end

def game_loop control
  tv = 0.0
  rFd = []

  # set this for the first loop
  last_time = Time.now

  # clear out the file socket set
  $fSet = []

  # add control to the set
  $fSet << control

  # do this untill the program is shutdown
  while !$shut_down
    # set current_time
    $current_time = Time.now

    # copy the socket set
    rFd = $fSet.dup

    # wait for something to happen
    # Poll our socket interest set
    rFd, dummy, dummy = select(rFd, nil, nil, tv)

    # check for new connections
    if rFd && rFd.include?(control)
      newConnection = control.accept
      if newConnection
        new_socket newConnection
      end
    end

    # poll sockets in the socket list
    $dsock_list.each do |dsock|
      #
      # Close sockects we are unable to read from.

      if rFd && rFd.include?(dsock.control) && !dsock.read_from_socket
        dsock.close_socket false
        next
      end

      # Ok, check for a new command
      dsock.next_cmd_from_buffer

      # Is there a new command pending ?
      if !dsock.next_command.empty?
        # figure out how to deal with the incoming command
        case dsock.state
        when :state_new_name, :state_new_password, :state_verify_password, :state_ask_password
          dsock.handle_new_connections dsock.next_command
        when :state_playing
          dsock.handle_cmd_input dsock.next_command
        else
          bug "Descriptor in bad state."
        end
        dsock.next_command = ''
      end

      # if the player quits or get's disconnected
      next if dsock.state == :state_closed

      # Send all new data to the socket and close it if any errors occour
      if !dsock.flush_output
        dsock.close_socket false
      end
    end

    # call the event queue
    heartbeat

    #
    # Here we sleep out the rest of the pulse, thus forcing
    # RocketMud to run at PULSES_PER_SECOND pulses each second.
    # get the time right now, and calculate how long we should sleep
    sleep_time = last_time - Time.now + (1.0 / PULSES_PER_SECOND)
    # if secs < 0 we don't sleep, since we have encountered a laghole
    if sleep_time > 0
      sleep sleep_time
      next
    end

    load_control

    # reset the last time we where sleeping
    last_time = Time.now

    # recycle sockets
    $dsock_list.each do |dsock|
      next if dsock.state != :state_closed

      # remove the socket from the socket list
      $dsock_list.delete dsock

      # close the socket
      dsock.control.close
    end
  end # while
end

#
# New_socket()
#
# Initializes a new socket, get's the hostname
# and puts it in the active socket_list.
def new_socket sock
  #
  # allocate some memory for a new socket if
  # there is no free socket in the free_list
  sock_new = SockDesc.new sock

  # attach the new connection to the socket list
  $fSet << sock

  # set the socket as non-blocking
  sock.fcntl Fcntl::F_SETFL, Fcntl::O_NONBLOCK unless RUBY_PLATFORM =~ /win32/

  # update the linked list of sockets
  $dsock_list << sock_new

  # send the greeting
  sock_new.text_to_buffer $greeting
  sock_new.text_to_buffer "What is your name? "

  # initialize socket events
  init_events_socket sock_new

  # everything went as it was supposed to
  return true
end

def termguard(sig)
  bug "The server is shutting down, attempting to close MUD."
  buf = sprintf("\r\nThe server is shutting down!\r\n");

  # inform all players and save them
  $dsock_list.each do |dsock|
    dsock.text_to_socket buf
    if dsock.state == :state_playing && dsock.player
      save_player dsock.player
    end
  end

  # close MUD
  exit 1
end

if __FILE__ == $0
  Signal.trap("INT", method(:termguard))
  Signal.trap("TERM", method(:termguard))
  Signal.trap("KILL", method(:termguard))

  load_control
  # note that we are booting up
  log_string "Program starting."

  # initialize the event queue - part 1
  init_event_queue 1

  # initialize the socket
  servsock = TCPServer.new '0.0.0.0', MUDPORT
  servsock.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true) unless RUBY_PLATFORM =~ /cygwin/
  servsock.setsockopt(Socket::SOL_SOCKET, Socket::SO_LINGER, [0,0].pack('ii'))
  servsock.fcntl Fcntl::F_SETFL, Fcntl::O_NONBLOCK unless RUBY_PLATFORM =~ /win32/

  # load all external data
  load_muddata

  # initialize the event queue - part 2
  init_event_queue 2

  # main game loop
  game_loop servsock

  # close down the socket
  servsock.close

  # terminated without errors
  log_string "Program terminated without errors."
  exit 0
end
