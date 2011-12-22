#
# RocketMUD was written by Jon Lambert, 2006.
# It is based on SocketMUD(tm) written by Brian Graversen.
# This code is released to the public domain.
#

class Mobile
  attr_accessor :socket, :events, :name, :password, :level

  def initialize
    # use conditional initialization
    @socket   ||= nil
    @events   ||= []
    @name     ||= nil
    @password ||= nil
    @level    ||= LEVEL_PLAYER
  end
  public :initialize   # make it public so we can call it after YAML load

  def is_admin?
    @level > LEVEL_PLAYER ? true : false
  end

  def to_yaml_properties
    ['@name', '@password', '@level']
  end

  #
  # Text_to_mobile()
  #
  # If the mobile has a socket, then the data will
  # be send to text_to_buffer().
  def text_to_mobile txt
    if @socket
      @socket.text_to_buffer txt
      @socket.bust_prompt = true
    end
  end

  def free_mobile
    $dmobile_list.delete self
    @socket.player = nil if @socket
    @events.each {|e| e.dequeue_event}
  end

  # function   :: event_isset?
  # arguments  :: the type of event
  #
  # This function checks to see if a given type of event is enqueued/attached
  # to the mobile, and if it is, it will return a pointer to this event.
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
  # This function will dequeue all events of a given type from the mobile.
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
  # This function attaches an event to a mobile, and sets all the correct
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
    event.ownertype  = :event_owner_dmob
    event.owner = self

    # attach the event to the mobiles local list
    @events << event

    # attempt to enqueue the event
    if enqueue_event(event, delay) == false
      bug "add_event: event type %d failed to be enqueued.", event.type
    end
  end


  # commands follow

  def cmd_say arg
    if arg == ''
      text_to_mobile "Say what?\r\n"
      return
    end
    communicate self, arg, :comm_local
  end

  def cmd_quit arg
    # log the attempt
    log_string sprintf("%s has left the game.", @name)
    save_player self
    @socket.player = nil
    free_mobile
    @socket.close_socket false
  end

  def cmd_shutdown arg
    $shut_down = true
  end

  def cmd_commands arg
    col = 0
    buf = sprintf "    - - - - ----==== The full command list ====---- - - - -\r\n\r\n"
    $tabCmd.each do |c|
      next if @level < c.level
      buf << sprintf(" %-16.16s", c.cmd_name)
      col += 1
      buf << "\r\n" if col % 4 == 0
    end
    buf << "\r\n" if col % 4 > 0
    text_to_mobile buf
  end

  def cmd_who arg
    buf = " - - - - ----==== Who's Online ====---- - - - -\r\n"
    $dsock_list.each do |dsock|
      next if dsock.state != :state_playing
      xMob = dsock.player
      next if xMob == nil
      buf << sprintf(" %-12s   %s\r\n", xMob.name, dsock.hostname)
    end
    buf << " - - - - ----======================---- - - - -\r\n"
    text_to_mobile buf
  end

  def cmd_help arg
    if arg == ''
      col = 0
      buf = "      - - - - - ----====//// HELP FILES  \\\\\\\\====---- - - - - -\r\n\r\n"
      $help_list.each do |pHelp|
        buf << sprintf(" %-19.18s", pHelp.keyword)
        col += 1
        buf << "\r\n" if col % 4 == 0
      end
      buf << "\r\n" if col % 4 != 0
      buf << "\r\n Syntax: help <topic>\r\n"
      text_to_mobile buf
      return;
    end
    if !check_help self, arg
      text_to_mobile "Sorry, no such helpfile.\r\n"
    end
  end

  def cmd_save arg
    save_player self
    text_to_mobile "Saved.\r\n"
  end

  def cmd_linkdead arg
    found = false
    $dmobile_list.each do |xMob|
      if xMob.socket.nil?
        text_to_mobile sprintf("%s is linkdead.\r\n", xMob.name)
        found = true
      end
    end
    if !found
      text_to_mobile "Noone is currently linkdead.\r\n"
    end
  end

end


