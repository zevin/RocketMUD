#
# RocketMUD was written by Jon Lambert, 2006.
# It is based on SocketMUD(tm) written by Brian Graversen.
# This code is released to the public domain.
#
#
# This file contains the event data struture, global variables
# and specially defined values like MAX_EVENT_HASH.
#

# the event structure
class Event
  attr_accessor :fun, :argument, :passes, :owner, :bucket, :ownertype, :type


  def initialize f, t
    @fun        = f             # the function being called
    @type       = t             # event type :event_xxx_yyy

    @argument   = nil           # the text argument given (if any)
    @owner      = nil           # this is the owner of the event, we
                                # use a union to make sure any of the
                                # types can be used for an event.
    @passes     = 0             # how long before this event executes
    @bucket     = 0             # which bucket is this event in
    @ownertype  = :event_unowned # type of owner (unlinking req)
  end


  # function   :: dequeue_event()
  # arguments  :: the event to dequeue.
  #
  # This function takes an event which has _already_ been enqueued, and
  # removes it both from the event queue, and from the owners local list.
  # This function is usually called when the owner is destroyed or after
  # the event is executed.
  def dequeue_event
    # dequeue from the bucket
    $eventqueue[@bucket].delete self

    # dequeue from owners local list
    case @ownertype
    when :event_owner_game
      $global_events.delete self
    when :event_owner_dmob, :event_owner_dsocket
      @owner.events.delete self
    else
      bug "dequeue_event: event type %s has no owner.", @type
    end
  end

  # event_game_tick is just to show how to make global events
  # which can be used to update the game.
  #
  def event_game_tick
    # send a tick message to everyone
    $dmobile_list.each do |dMob|
      dMob.text_to_mobile "Tick!\r\n"
    end

    # enqueue another game tick in 10 minutes
    ev = Event.new :event_game_tick, :event_game_tick
    add_event_game ev, 10 * 60 * PULSES_PER_SECOND

    return false
  end

  def event_mobile_save
    # Check to see if there is an owner of this event.
    # If there is no owner, we return TRUE, because
    # it's the safest - and post a bug message.
    #
    dMob = @owner
    if dMob == nil
      bug "event_mobile_save: no owner."
      return true
    end

    # save the actual player file
    save_player dMob

    # enqueue a new event to save the pfile in 2 minutes
    ev = Event.new :event_mobile_save, :event_mobile_save
    dMob.add_event ev, 2 * 60 * PULSES_PER_SECOND

    return false
  end

  def event_socket_idle
    # Check to see if there is an owner of this event.
    # If there is no owner, we return TRUE, because
    # it's the safest - and post a bug message.
    #
    dSock = @owner
    if dSock == nil
      bug "event_socket_idle: no owner."
      return true
    end

    # tell the socket that it has idled out, and close it
    dSock.text_to_socket "You have idled out...\r\n\r\n"
    dSock.close_socket false

    # since we closed the socket, all events owned
    # by that socket has been dequeued, and we need
    # to return TRUE, so the caller knows this.
    #
    return true
  end

end


# function   :: enqueue_event()
# arguments  :: the event to enqueue and the delay time.
# ======================================================
# This function takes an event which has _already_ been
# linked locally to it's owner, and places it in the
# event queue, thus making it execute in the given time.

def enqueue_event event, game_pulses
  # check to see if the event has been attached to an owner
  if event.ownertype == :event_unowned
    bug "enqueue_event: event type %d with no owner.", event.type
    return false
  end

  # An event must be enqueued into the future
  if game_pulses < 1
    game_pulses = 1
  end

  # calculate which bucket to put the event in,
  # and how many passes the event must stay in the queue.

  bucket = (game_pulses + $current_bucket) % MAX_EVENT_HASH
  passes = game_pulses / MAX_EVENT_HASH

  # let the event store this information
  event.passes = passes
  event.bucket = bucket

  # attach the event in the queue
  $eventqueue[bucket] << event

  # success
  return true
end


# function   :: init_event_queue()
# arguments  :: what section to initialize.
#
# This function is used to initialize the event queue, and the first
# section should be initialized at boot, the second section should be
# called after all areas, players, monsters, etc has been loaded into
# memory, and it should contain all maintanence events.
def init_event_queue section
  if section == 1
    $eventqueue = Array.new(MAX_EVENT_HASH) {Array.new}
    $global_events = []
    $current_bucket = 0
  elsif section == 2
    event = Event.new :event_game_tick, :event_game_tick
    add_event_game event, 10 * 60 * PULSES_PER_SECOND
  end
end

# function   :: heartbeat()
# arguments  :: none
# ======================================================
# This function is called once per game pulse, and it will
# check the queue, and execute any pending events, which
# has been enqueued to execute at this specific time.
def heartbeat
  # current_bucket should be global, it is also used in enqueue_event
  # to figure out what bucket to place the new event in.
  $current_bucket = ($current_bucket + 1) % MAX_EVENT_HASH

  $eventqueue[$current_bucket].each do |event|
    # Here we use the event->passes integer, to keep track of
    # how many times we have ignored this event.
    if event.passes > 0
      event.passes -= 1
      next
    end

    # execute event and extract if needed. We assume that all
    # event functions are of the following prototype
    #
    # bool event_function ( EVENT_DATA *event );
    #
    # Any event returning TRUE is not dequeued, it is assumed
    # that the event has dequeued itself.
    ret = event.send event.fun
    if !ret
      event.dequeue_event
    end
  end
end


# function   :: add_event_game()
# arguments  :: the event and the delay
# ======================================================
# This funtion attaches an event to the list og game
# events, and makes sure it's enqueued with the correct
# delay time.
def add_event_game event, delay
  # check to see if the event has a type
  if event.type == :event_none
    bug "add_event_game: no type."
    return
  end

  # check to see of the event has a callback function
  if event.fun == nil
    bug "add_event_game: event type %d has no callback function.", event.type
    return
  end

  # set the correct variables for this event
  event.ownertype = :event_owner_game

  # attach the event to the gamelist
  $global_events << event

  # attempt to enqueue the event
  if enqueue_event(event, delay) == false
    bug "add_event_game: event type %d failed to be enqueued.", event.type
  end
end

# function   :: init_events_mobile()
# arguments  :: the mobile
# ======================================================
# this function should be called when a player is loaded,
# it will initialize all updating events for that player.
def init_events_player dMob
  # save the player every 2 minutes
  event = Event.new :event_mobile_save, :event_mobile_save
  dMob.add_event event, 2 * 60 * PULSES_PER_SECOND
end

# function   :: init_events_socket()
# arguments  :: the mobile
# ======================================================
# this function should be called when a socket connects,
# it will initialize all updating events for that socket.
def init_events_socket dSock
  # disconnect/idle
  event = Event.new :event_socket_idle, :event_socket_idle
  dSock.add_event event, 5 * 60 * PULSES_PER_SECOND
end

