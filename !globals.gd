extends Node
# ProTracker period table
const period_table = [
	1712,1616,1524,1440,1356,1280,1208,1140,1076,1016,960,907,
	856,808,762,720,678,640,604,570,538,508,480,453,
	428,404,381,360,339,320,302,285,269,254,240,226,
	214,202,190,180,170,160,151,143,135,127,120,113,
	107,101,95,90,85,80,75,71,67,63,60,56,
	53,50,47,45,42,40,37,35,33,31,30,28,
	26,25,23,22,21,20,18,17,16,
	]  #The last line of values is UNOFFICIAL and only used for OpenMPT compatibility!
	
const note_string = ['C-', 'C#', 'D-', 'D#', 'E-', 'F-',
					 'F#', 'G-', 'G#', 'A-', 'A#', 'B-']

#Finetune sample rate lookup table.  NTSC, NOT PAL! FT2 standard. Most amigas use PAL
const FINETUNE_FREQ = [8363,8413,8463,8529,8581,8651,8723,8757,
						7895,7941,7985,8046,8107,8169,8232,8280]


#Gets the native sampling Hz rate needed to produce iteration value
const CLOCK_SPEED = 7093789.2   #m68k running at 7.09 MHz (PAL)
func get_sample_rate(period):
	if period == 0:  return 0
	return CLOCK_SPEED / float(period*2)


func bsearch_closest(arr, l, r, x): 
	# Check base case 
	var mid:int = l + (r - l)/2
	if r >= l: 
  
		# If element is present at the middle itself 
		if arr[mid] == x: 
			return mid 
		  
		# If element is smaller than mid, then it  
		# can only be present in left subarray 
		elif arr[mid] > x: 
			return bsearch_closest(arr, mid + 1, r, x)   
		# Else the element can only be present  
		# in right subarray 
		else: 
			return bsearch_closest(arr, l, mid-1, x) 
			
  
	else: 
		# Element is not present in the array.  Return closest value
		return mid


#Packs arbitrary bits into a big-endian int.  TODO:  little endian swap
func packbits(bits):
	assert (bits.size <= 32)
	var output = 0
	for b in bits:
		output <<= 1
		output |= b
		
	return output

#Converts decimal integer to a hex string.
func int2hex(n, pad=0):
	assert (typeof(n) == TYPE_INT)
	var hexaDeciNum:PoolByteArray = PoolByteArray([])
	
	if n == 0: hexaDeciNum.append(48)
	
	while n != 0:
		var temp = n % 16
		
		if temp < 10:
			hexaDeciNum.append(temp + 48)
		else:
			hexaDeciNum.append(temp + 55)
		
		n /= 16  #Next digit
		
	
	while pad-hexaDeciNum.size()>0:
		hexaDeciNum.append(48)
		pad -=1
	hexaDeciNum.invert()
	return hexaDeciNum.get_string_from_ascii()
		

#This maybe unnecessary. Here we're mapping the effect to Impulse Tracker format.
#Stolen from ChibiTracker
func mod2impulse_effect(note, cmd):
	match cmd:
		0x0:  #Arpeggio
			if note.parameter > 0:
				note.command='J'
	
		0x1:  #Slide up
			note.command='F'
	
		0x2:  #Slide down
			note.command='E'
	
		0x3:  #Tone Portamento
			note.command='G'
	
		0x4:  #Vibrato
			note.command='H'
	
		0x5:  #Tone Portamento + Volume Slide
			note.command='L'
	
		0x6:  #Vibrato + Volume Slide
			note.command='K'
	
		0x7:  #Tremolo
			note.command='R'
	
		0x8:  #Reserved  (FastTracker:  Set Panning)
			note.command='X'
	
		0x9:  #Set Sample offset
			note.command='O'
			
	
		0xA:  #Volume slide
			note.command='D'
			
	
		0xB:  #Position jump
			note.command='B'
			
	
		0xC:  #Volume slide
			note.volume=note.parameter;
			if note.volume > 64:  note.volume = 64;  #Huh what?
			note.parameter=0;
			
	
		0xD:  #Pattern Break
			
			note.command='C'
			note.parameter= (note.parameter>>4)*10 + note.parameter&0xF;
			
	
		0xE: #All the stupid effects are packed here
			note.command='S'
			
			match (note.parameter>>4):
				0x0:  #Set lowpass filter (7000hz) on/off.  TODO
					pass
					
				0x1:  #Fine portamento up
					note.command='F'
					note.parameter=0xF0|(note.parameter&0xF);			
				0x2: #Fine portamento down
					note.command='E'
					note.parameter=0xF0|(note.parameter&0xF);

				0x3:  #Glissando control for portamentos. (fine/semitones).
					pass  #TODO:  IMPLEMENT ME
					#S10 / S1x

				0x4: #Set vibrato waveform.  S3x
					note.command='S'
					note.parameter=0x30|(note.parameter&0x3);

				0x6:  #SBx. Loop pattern x times. If x==0, it's loop start point.
					note.command='S'
					note.parameter=0xB0|(note.parameter&0xF);

				0x7:  #Set Tremolo waveform.  See 0x4.
					note.command='S'
					note.parameter=0x40|(note.parameter&0x3);


				0x8:
					#Nothing.  It is a mystery.......
					note.command='S' 


				0x9:  #Retrigger note.
					note.command='Q'
					note.parameter=(note.parameter&0xF);
					
			
				0xA:  #Fine volume slide up.
					note.command='D'
					note.parameter=0xF|((note.parameter&0xF)<<4);
				0xB:  #Fine volume slide down.
					note.command='D'
					note.parameter=0xF0|(note.parameter&0xF);
					
			
				0xC:  #Note cut after x ticks.
					pass  #TODO:  IMPLEMENT ME!  SCx
				0xD:  #Note delay until x ticks.
					note.command='S' 
					#The parameter bits are the same in IT as MOD.

				0xE: #Pattern delay (SEx). Delay x rows.   sexy
					note.command='S'
					note.parameter=0x60|(note.parameter&0xF);

				0xF:  #Invert Loop / Funk-it.  An even bigger mystery than 0x8 :)
					pass  #Unimplemented

				_:  #Default.  This should never happen
					
					note.command=""
					note.parameter=0

	
		0xF:  #Speed / Tempo
			
			if note.parameter<32:  #Speed
				note.command='A'
			else:   #tempo
				note.command='T'
			

#Converts a period value to a note string.
func period2note(period):
	if period == 0: return "..."
	var pos = period_table.find(period) 
#		var pos = global.period_table.bsearch_custom(period, self, "comparator") 
	if pos == -1:
		#Finetune value has messed with this, figure out a better way
		#To determine the closest note instead.  TODO
		return "???"  
	else:
		var octave = pos / 12
		return note_string[pos%12] + String(octave)
