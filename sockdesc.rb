#
# RocketMUD was written by Jon Lambert, 2006.
# It is based on SocketMUD(tm) written by Brian Graversen.
# This code is released to the public domain.
#

# This file contains the socket code, used for accepting
# new connections as well as reading and writing to
# sockets, and closing down unused sockets.
#

class SockDesc
  attr_accessor :control, :state
  attr_accessor :player, :events, :hostname, :inbuf, :outbuf
  attr_accessor :next_command, :bust_prompt


  def initialize sock
    @control = sock
    @state   =  :state_new_name   # Connection states symbols used
                                  #  state_new_name        = 0
                                  # :state_new_password    = 1
                                  # :state_verify_password = 2
                                  # :state_ask_password    = 3
                                  # :state_playing         = 4
                                  # :state_closed          = 5
    @player = nil
    @events = []
    @hostname = sock.peeraddr[2]
    @inbuf = ""
    @outbuf = ""
    @next_command = ""
    @bust_prompt = false
  end

  #
  # Text_to_socket()
  #
  # Sends text directly to the socket,
  # will compress the data if needed.
  def text_to_socket txt
    n = @control.send(txt, 0)
    # save unsent data for next call
    txt.slice!(0...n) # Only has an effect if txt parameter a reference.
    return true
  rescue Exception
    log_string "text_to_socket: Error"
    log_string $!.to_s
    return false
  end

  def next_cmd_from_buffer
    # if theres already a command ready, we return
    return if !@next_command.empty?

    # if there is nothing pending, then return
    return if @inbuf.empty?

    # check how long the next command is
    sz = 0
    while !@inbuf[sz].nil? && @inbuf[sz] != ?\n && @inbuf[sz] != ?\r
      sz += 1
    end

    # we only deal with real commands
    if @inbuf[sz].nil?
      return
    end

    telopt = 0
    # copy the next command into next_command
    sz.times do |i|
      if @inbuf[i].chr == IAC.chr
        telopt = 1
      elsif telopt == 1 && (@inbuf[i].chr == DO.chr || @inbuf[i].chr == DONT.chr)
        telopt = 2;
      elsif telopt == 2
        telopt = 0
      elsif @inbuf[i].chr =~ /[[:print:]]/
        @next_command << @inbuf[i].chr
      end
    end

    # skip forward to the next line
    while !@inbuf[sz].nil? && (@inbuf[sz] == ?\n || @inbuf[sz] == ?\r)
      @bust_prompt = true   # seems like a good place to check
      sz += 1
    end

    # move the context of inbuf down
    @inbuf.slice!(0..sz)
  end

  #
  # Close_socket()
  #
  # Will close one socket directly, freeing all
  # resources and making the socket availably on
  # the socket free_list.
  def close_socket reconnect
    return if @state == :state_closed

    # remove the socket from the polling list
    $fSet.delete @control

    if @state == :state_playing
      if reconnect
        text_to_socket "This connection has been taken over.\r\n"
      elsif @player
        @player.socket = nil
        log_string "Closing link to %s", @player.name
      end
    elsif @player
      @player.free_mobile
    end

    # dequeue all events for this socket
    @events.each do |ev|
      ev.dequeue_event
    end

    # set the closed state
    @state = :state_closed
  end

  def flush_output
    # nothing to send
    if @outbuf.size == 0 && !(@bust_prompt && @state == :state_playing)
      return true
    end

    # bust a prompt
    if @state == :state_playing && @bust_prompt
      text_to_buffer "\r\nRocketMud:> "
      @bust_prompt = false
    end

    #
    # Send the buffer, and return FALSE
    # if the write fails.
    if !(text_to_socket @outbuf)
      return false
    end

    # Success
    return true
  end

  #
  # Read_from_socket()
  #
  # Reads one line from the socket, storing it
  # in a buffer for later use. Will also close
  # the socket if it tries a buffer overflow.
  def read_from_socket
    # start reading from the socket
    input = @control.recv(MAX_BUFFER)
    if !input || input.empty?
      log_string "Read_from_socket: EOF"
      return false
    end
    @inbuf << input
    # check for buffer overflows, and drop connection in that case
    if @inbuf.size > MAX_BUFFER
      @inbuf = ''
      text_to_socket "\r\n!!!! Input Overflow !!!!\r\n"
      return false
    else
      return true
    end
  rescue Errno::EWOULDBLOCK
    return true
  rescue Exception
    log_string "Read_from_socket: Error"
    log_string $!.to_s
    return false
  end

  #
  # Text_to_buffer()
  #
  # Stores outbound text in a buffer, where it will
  # stay untill it is flushed in the gameloop.
  #
  # Will also parse ANSI colors and other tags.
  def text_to_buffer txt
    output = ""
    underline = bold = false
    last = -1

    if txt.size > MAX_BUFFER
      log_string "text_to_buffer: buffer overflow."
      return
    end

    # always start with a leading space
    if @outbuf.empty?
      @outbuf = "\r\n"
    end

    i = 0
    while i < txt.size
      if txt[i] == ?#
        i += 1
        # toggle underline on/off with #u
        if txt[i] == ?u
          i += 1
          if underline
            underline = false
            output << "\e[0"
            output << ';1' if bold
            if last != -1
              output << ';'
              output << $ansi_table[last][1]
            end
            output << 'm'
          else
            underline = true
            output << "\e[4m"
          end
        # parse ## to #
        elsif txt[i] == ?#
          i += 1
          output << '#'
        # #n should clear all tags
        elsif txt[i] == ?n
          i += 1
          if last != -1 || underline || bold
            underline = false
            bold = false
            output << "\e[0m"
          end
          last = -1
        # check for valid color tag and parse
        else
          validTag = false
          $ansi_table.size.times do |j|
            if txt[i] == $ansi_table[j][0]
              validTag = true
              # we only add the color sequence if it's needed
              if last != j
                cSequence = false
                # escape sequence
                output << "\e["
                # remember if a color change is needed
                cSequence = true if last == -1 || last / 2 != j / 2
                # handle font boldness
                if bold && $ansi_table[j][2] == false
                  output << '0'
                  bold = false
                  output << ";4" if underline
                  # changing from bold wipes the old color
                  output << ';'
                  cSequence = true
                elsif !bold && $ansi_table[j][2] == true
                  output << '1'
                  bold = true
                  output << ';' if cSequence
                end
                # add color sequence if needed
                output << $ansi_table[j][1] if cSequence
                output << 'm'
              end
              # remember the last color
              last = j
            end
          end
          # it wasn't a valid color tag
          if !validTag
            output << '#'
          else
            i += 1
          end
        end
      else
        output << txt[i].chr
        i += 1
      end
    end # while

    # and terminate it with the standard color
    if last != -1 || underline || bold
      output << "\e[0m"
    end

    # check to see if the socket can accept that much data
    if @outbuf.size + output.size > MAX_OUTPUT
      bug "Text_to_buffer: ouput overflow on %s.", @hostname
      return
    end

    # add data to buffer
    @outbuf << output
  end

  def handle_new_connections arg
    case @state
    when :state_new_name
      if !check_name(arg) # check for a legal name
        text_to_buffer "Sorry, that's not a legal name, please pick another.\r\nWhat is your name? "
        return
      end
      arg.capitalize!
      log_string "%s is trying to connect.", arg

      # Check for a new Player
      p_new = load_player arg
      if p_new.nil?
        p_new = Mobile.new
        # give the player it's name
        p_new.name = arg.dup
        # prepare for next step
        text_to_buffer "Please enter a new password: "
        @state = :state_new_password
      else # old player
        # prepare for next step
        text_to_buffer "What is your password? "
        @state = :state_ask_password
      end
      text_to_buffer DONT_ECHO
      # socket <-> player
      p_new.socket = self
      @player = p_new

    when :state_new_password
      if arg.size < 5 || arg.size > 12
        text_to_buffer "Between 5 and 12 chars please!\r\nPlease enter a new password: "
        return
      end
      @player.password = arg.crypt(@player.name)
      @player.password.size.times do |i|
        if @player.password[i].chr == '~'
          text_to_buffer "Illegal password!\r\nPlease enter a new password: "
          return
        end
      end
      text_to_buffer "Please verify the password: "
      @state = :state_verify_password

    when :state_verify_password
      if @player.password == arg.crypt(@player.name)
        text_to_buffer DO_ECHO
        # put him in the list
        $dmobile_list << @player
        log_string "New player: %s has entered the game.", @player.name
        # and into the game
        @state = :state_playing
        text_to_buffer $motd
        # initialize events on the player
        init_events_player @player
        # strip the idle event from this socket
        strip_event :event_socket_idle
      else
        @player.password = nil
        text_to_buffer "Password mismatch!\r\nPlease enter a new password: "
        @state = :state_new_password
      end

    when :state_ask_password
      text_to_buffer DO_ECHO
      if arg.crypt(@player.name) == @player.password
        if (p_new = check_reconnect(@player.name)) != nil
          # attach the new player
          @player.free_mobile
          @player = p_new
          p_new.socket = self

          log_string "%s has reconnected.", @player.name

          # and let him enter the game
          @state = :state_playing
          text_to_buffer "You take over a body already in use.\r\n"

          # strip the idle event from this socket
          strip_event :event_socket_idle
        elsif (p_new = load_player(@player.name)) == nil
          text_to_socket "ERROR: Your pfile is missing!\r\n"
          @player.free_mobile
          @player = nil
          close_socket false
          return
        else
          # attach the new player
          @player.free_mobile
          @player = p_new
          p_new.socket = self

          # put him in the active list
          $dmobile_list << p_new

          log_string "%s has entered the game.", @player.name

          # and let him enter the game
          @state = :state_playing
          text_to_buffer $motd

          # initialize events on the player
          init_events_player @player

          # strip the idle event from this socket
          strip_event :event_socket_idle
        end
      else
        text_to_socket "Bad password!\r\n"
        @player.free_mobile
        @player = nil
        close_socket false
      end
    else
      bug "Handle_new_connections: Bad state."
    end
  end


  def handle_cmd_input arg
    command = ""
    found_cmd = false
    dMob = @player
    return if dMob == nil

    one_arg! arg, command

    $tabCmd.each do |c|
      next if c.level > dMob.level

      if is_prefix command, c.cmd_name
        found_cmd = true
        dMob.send(c.cmd_funct, arg)
        break
      end
    end

    if !found_cmd
      dMob.text_to_mobile "No such command.\r\n"
    end
  rescue
    log_string "handle_cmd_input Error"
    log_string $!.to_s
  end

  # function   :: event_isset?
  # arguments  :: the type of event
  #
  # This function checks to see if a given type of event is enqueued/attached
  # to the socket, and if it is, it will return a pointer to this event.
  def event_isset? type
    @events.each do |event|
      if event.type == type
        return event
      end
    end
    return nil
  end

  # function   :: strip_event
  # arguments  :: the type of event
  #
  # This function will dequeue all events of a given type from the socket.
  def strip_event type
    @events.each do |event|
      if event.type == type
        event.dequeue_event
      end
    end
  end

  # function   :: add_event
  # arguments  :: the event and the delay
  #
  # This function attaches an event to a socket, and sets all the correct
  # values, and makes sure it is enqueued into the event queue.
  def add_event event, delay
    # check to see if the event has a type
    if event.type == :event_none
      bug "add_event: no type."
      return
    end

    # check to see of the event has a callback function
    if event.fun == nil
      bug "add_event: event type %d has no callback function.", event.type
      return
    end

    # set the correct variables for this event
    event.ownertype   = :event_owner_dsocket
    event.owner = self

    # attach the event to the sockets local list
    @events << event

    # attempt to enqueue the event
    if enqueue_event(event, delay) == false
      bug "add_event_socket: event type %d failed to be enqueued.", event.type
    end
  end


end

