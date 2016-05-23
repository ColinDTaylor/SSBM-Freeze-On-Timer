_backup:
    subi	sp, sp, 40
    stw   r0, 4(sp)
    stw		r3, 8(sp)
    stw		r4, 12(sp)
    stw		r5,	16(sp)
    stw   r6, 20(sp)
    stw		r31,24(sp) #backing this up just in case, since it's on the injection site
    mfctr	r3
    stw		r3, 28(sp)
    mflr  r3
    stw   r3, 32(sp)
    nop

_if_not_in_match:
    lis   r3,      0x8045
    ori   r3, r3,  0x3080 #loading in the addr of static p1 block
    li r4, 4
    mtctr r4   # move the value 4 into ctr for the loop (4 players)
    _check_if_match_loop:
        lwz r4, 0(r3)
        cmpwi  r4, 0x02
        beq   _check_flag2 #0x02 indicates that player is in-match, proceed
        nop
        addi  r3, r3, 0xE90  # the players are 0xE90 apart
        bdnz  _check_if_match_loop # loop this code until we've checked all 4
        nop                        # or have found a 0x02
    b   _restore         #if players in match == 0, exit code
    nop

_check_flag2 # we need to check if last frame was the unfreeze frame
    lis     r3,	0x8000
    ori     r3,r3,	0x2D6E 	#0x80002D6E is the temp. location of my flags
    lhz     r4, 0(r3)
    andi.   r5, r4, 0x0010
    beq     _pause_status   # if the flag bit == 0, branch onwards
    xori    r4, r4, 0x0010  # else, flip that flag off
    lis     r3, 0x8047
    ori     r3,r3, 0x9d68	  #0x80479d68 is a byte that controls pauses
    stb     0,0(r3)         #store 0 in the pause byte, indicating normal gameplay

_pause_status:
    lis     r3, 0x8047
    ori     r3,r3, 0x9d68	     #0x80479d68 is a byte that controls pauses
    lbz     r4, 0(r3)         #We only really need to check the first byte
    cmpwi   r4, 2             #0x02 in the pause byte is normal pause
    beq     _restore          #gameplay is paused, skip everything
    nop

_if_frozen:
    lis     r3, 0x8047
    ori     r3,r3, 0x9d68	    #0x80479d68 is a word controlling pauses
    lwz     r4, 0(r3)
    cmpwi   r4, 0             #at 0, the frame advance mode is off completely
    beq     _toggle           #if not frozen, branch to toggle check
    #bl      _pause_status
    nop

    _inputs_frozen:         #we want to check for z (frame advance) or start (unfreeze)
    li     r5, 0x1000       #bitmaps: start = 0x1000, z = 0x0010
    bl	   _controllercheck #r5 is the input for _controllercheck, and the output
    nop
    cmpwi   r5, 0
    bgt	   	_unset_freeze   #if somone pressed start, we need to unfreeze
    nop                     #otherwise, check for Z
    li     r5, 0x0010
    bl	   _controllercheck #same thing as last time, but this time checking Z
    nop
    cmpwi   r5, 0
    beq     _restore        #if nobody pressed Z, nothing happens at all
    nop
    addi    r4, r4, 0x0100   #if Z pressed, advance frame by setting FA to 0x01010100
    stw     r4, 0(r3)       #and store it back in the address (adding 1 actually causes a frame advance)
    b       _restore        #then restore, we don't need any other functions this frame
    nop

_toggle:
    li  r5, 0x121             #0x121 = 100100001 = input mask for R+A+dpadL
    bl  _controllercheck
    nop
    lis     r3,	0x8000
    ori     r3,r3,	0x2D6C 	#0x80002D6C is the temp. location of my timer + flags
    cmpwi r5, 1             #see if _controllercheck returned true
    bne   _check_flag       #if not, branch
    lbz     r4, 0x3(r3)     #this is the flag used to toggle the code
    xori    r4, r4, 1       #negate 0x80002D6F if R+A+dpadL was pressed by anyone
    stb     r4, 0x3(r3)
    lis     r4, 0x8017
    ori     r4, r4, 0x4338
    mtctr   r4 #branch to the play menu forward sfx function
    bctrl
    li      r4, 0
    sth     0, 0(r3)       #reset the timer on each toggle, not optimal but whatevs
    _check_flag:
    lbz     r4, 0x3(r3)
    cmpwi   r4, 0
    beq     _restore        #if the flag is not flipped, leave code
    nop

_increment_timer:
    #lis     r3,	0x8000
    #ori     r3,r3,	0x2D6C 	#0x80002D6C is the temp. location of my timer
    lhz     r4, 	0(r3)
    addi    r4,r4,	1		    #add 1 to the current amount in the timer
    sth     r4,	0(r3)	      #store the result of that add back in the address
_freeze_on_interval:
    li      r5, 3600	      #this is the number of frames we're playing before a pause
    divw    r3,r4,r5	      #divide the timer by our constant ex: 615/300 = 2
    mullw   r3,r3,r5        #multiply the result by that constant ex: 2*300 = 600
    subf.   r3,r3,r4        #subtract the result from the timer ex: 615 - 600 = 15
    bgt     _restore	      #branch to _restore if the result > 0
    nop
    b       _set_freeze     #else, timer must be a multiple of out constant so freeze
    nop

_set_freeze:
    lis   r5, 0x0101
    addi  r5, r5, 1          #adding 1 to r5 to get it to 0x01010001
    lis 	r3, 0x8047         #load up the frame advance address, left half
    ori 	r3, r3, 0x9d68
    stb		r5, 0(r3)          #store 0x01010001, forces dev mode frame advance
    b     _restore
    nop

_unset_freeze:
    lis   r5, 0x0202        # 0x0202 is normal pause, I use this to trick the game into thinking it was paused
    addi  r5,r5, 0x0001     # this causes it to "unpause" immediately on reading the player's start input
    lis 	r3, 0x8047        # thus stopping a pause from occuring immediately on unfreeze.
    ori 	r3, r3, 0x9d68    # as far as I can tell, 0x00000001 seems to turn frame advance off
    stw		r5, 0(r3)         # store 0x02020001 in the frame advance address, unfreezes everything
    lis     r3,	0x8000      # set the prev. frame unfrozen flag, unsetting this next frame should fix pause issues
    ori     r3,r3,	0x2D6E
    lhz     r4, 0(r3)
    addi    r4, r4, 0x0010
    sth     r4, 0(r3)
    b     _restore #_toggle           #now that the game is unfrozen, we need to check toggle status
    nop

_controllercheck:           #check all 4 ports for inputs matching AND mask in r5
    _controllercheck:
    subi	sp, sp, 28
    stw		r3, 4(sp)
    mfctr	r3
    stw		r3, 20(sp)
    stw     r4, 8(sp)
    stw		r6, 16(sp)
    li      r3, 4
    mtctr   r3
    lis     r3, 0x804C
    ori	r3,r3, 0x1FAC
    li 		r6, 0
    b       _first_loop_startpoint
    nop
    _controllercheck_loop:
        addi    r3, r3, 0x44      #inputs for each player port are 0x44 apart
        _first_loop_startpoint:
        lwz     r4, 0x4(r3)       #first we check prev inputs
        and     r4, r4, r5
        cmpw    r4, r5
        beq     _cc_fail_check    #fail the check if mask matched prev. input
        nop                       #so holding won't register multiple times
        lwz     r4, 0(r3)
        and     r4, r4, r5
        cmpw    r4, r5
        bne  _cc_continue_loop    #if the result of the AND != the mask, next port
        nop
        li     r6, 1
        _cc_continue_loop:
        bdnz    _controllercheck_loop
        nop
        cmpwi   r6, 0
        beq     _cc_fail_check
        nop
        li		r5, 1
        b       _restore_cc
        nop

    _cc_fail_check:
    li     r5, 0
    b		_restore_cc
    nop

    _restore_cc:
    lwz		r3, 20(sp)
    mtctr	r3
    lwz		r3, 4(sp)
    lwz		r4, 8(sp)
    lwz		r6, 16(sp)
    addi	sp, sp, 28
    blr

_restore:
    lwz   r3, 32(sp)
    mtlr  r3
    lwz   r3, 28(sp)
    mtctr	r3
    lwz		r0, 4(sp)
    lwz		r3, 8(sp)
    lwz		r4, 12(sp)
    lwz   r5, 16(sp)
    lwz   r6, 20(sp)
    lwz		r31, 24(sp)
    addi	sp, sp, 40
    lwz	r0, 0x000C (r25)  # This is the instruction we wrote over
    nop
    #what
