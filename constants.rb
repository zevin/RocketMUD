#
# RocketMUD was written by Jon Lambert, 2006.
# It is based on SocketMUD(tm) written by Brian Graversen.
# This code is released to the public domain.
#

########################
# Standard definitions #
########################

# A few globals
PULSES_PER_SECOND =    4                   # must divide 1000 : 4, 5 or 8 works
MAX_BUFFER        = 1024                   # seems like a decent amount
MAX_OUTPUT        = 2048                   # well shoot me if it isn't enough
MUDPORT           = 9009                   # just set whatever port you want

# player levels
LEVEL_GUEST          =  1  # Dead players and actual guests
LEVEL_PLAYER         =  2  # Almost everyone is this level
LEVEL_ADMIN          =  3  # Any admin without shell access
LEVEL_GOD            =  4  # Any admin with shell access

#######################
#    Telnet support   #
#######################

IAC = 255     # interpret as command:
WONT = 252     # I won't use option
WILL = 251     # I will use option
DO   = 253  # Do option
DONT = 254  # Dont do option
TELOPT_ECHO = 1   # echo

DO_ECHO     = IAC.chr + WONT.chr + TELOPT_ECHO.chr
DONT_ECHO     = IAC.chr + WILL.chr + TELOPT_ECHO.chr

#########################
# End of Telnet support #
#########################

# the size of the event queue
MAX_EVENT_HASH =       128

