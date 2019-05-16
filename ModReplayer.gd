extends Control
#Playback system
var module = Module.new()
var buf:AudioStreamGeneratorPlayback  #Playback buffer
var isPlaying = false

var bufferdata  #PoolVector2Array , used for scopes

var sampleControls = []  #References to sample info controls

func _ready():
	#Bank 0
	for i in range(16):
		var p = preload("res://InstHBox.tscn").instance()
		p.name = "Sample%s" % i
		p.set_num(i)
		$Tabs/Bank0/VBox.add_child(p)
		sampleControls.append(p)
		p.owner = self

	#Bank 1
	for i in range(15):
		var p = preload("res://InstHBox.tscn").instance()
		p.name = "Sample%s" % (i+15)
		p.set_num(i+16)
		$Tabs/Bank1/VBox.add_child(p)
		sampleControls.append(p)
		p.owner = self

	buf = $Player.get_stream_playback()
	module.playback_rate = $Player.stream.mix_rate

	_on_FileDialog_file_selected("res://test.mod")

func _process(delta):
	#Do fill buffer if song is playing and it is requested.
	if isPlaying:
		fill_buffer()
		$Orders.text = "%s\n%s" % [module.channels[3].working_effect,
								   module.channels[3].volume_mod]


func _physics_process(delta):
	if bufferdata == null:  return
	var pts = []
	for i in range(0, bufferdata.size(), bufferdata.size() / 128):
		if i > 512:  break
		var p = bufferdata[i].x
		pts.append(Vector2(pts.size(), 64 + p*64))
	$Pattern/Line2D.points = pts

	
func fill_buffer(var frames=-1):
	var frames_to_fill = buf.get_frames_available()
	if frames >=0:  frames_to_fill = frames
	bufferdata = module.fill_buffer(frames_to_fill)
#	while frames_to_fill > 0:
#		buf.push_frame(Vector2(randf(), randf()))
#		frames_to_fill -= 1

	buf.push_buffer(bufferdata)

	$PlaybackPosition.text = "Tick %s\n" % module.tick
	$PlaybackPosition.text += "Row %s\nPattern %s" % [module.row, module.position]
	
#	while frames_to_fill > 0:
##		buf.push_frame()
#		frames_to_fill -= 1


func _on_Play_toggled(button_pressed):
	isPlaying = button_pressed
	if isPlaying:
		$Player.play()
	else:
		$Player.stop()

func _on_Stop_pressed():
	$Buttons/Play.pressed = false
	_on_Play_toggled(false)
	module.reset()

	buf.clear_buffer()

func play_sample(num):
	if !module.isReady:
		printerr("No module loaded.")
		return
	if num >= module.sampleBank.size():
		printerr("Only %s samples in bank. Samp not found"% module.sampleBank.size())
		return
	var samp = module.sampleBank[num]
	$SampleInfo.text = "Sample %s (%s):" % [num, samp.name]
	$SampleInfo.text +="\nlength: 		%s" % samp.length
	$SampleInfo.text +="\nfinetune:		%s" % samp.finetune
	$SampleInfo.text +="\nvolume: 		%s" % samp.volume
	$SampleInfo.text +="\nloop_start:		%s" % samp.loop_start
	$SampleInfo.text +="\nloop_end:		%s" % samp.loop_end

	$SamplePreview.stop()
	$SamplePreview.stream = samp.sample 
	$SamplePreview.play()


# ====================================================================== io
func _on_Open_pressed():
	$FileDialog.show_modal()
	pass # Replace with function body.


func _on_FileDialog_file_selected(path):
	module.load_module(path)

	$Pattern.clear()
	for i in 4:
		$Pattern.add_item("Channel %s" % (i+1), null, false)
		
	for row in module.patterns[0]:
		for note in row:
			$Pattern.add_item(note.get_info())

	buf.clear_buffer()
	fill_buffer($Player.stream.mix_rate * $Player.stream.buffer_length)
	
	$lblTitle.text = module.title

	$Orders.text = "Orders:"
	for i in module.positions_total:
		$Orders.text += "\n%s" % module.orders[i]

	for i in 16:
		var p = get_node("Tabs/Bank0/VBox/Sample%s" % i)
		p.set_text(module.sampleBank[i].name)
	for i in range(16,30):
		var p = get_node("Tabs/Bank1/VBox/Sample%s" % i)
		p.set_text(module.sampleBank[i].name)

#Storage sample
class Sample:
	# 30 bytes header
	var name = ""		# 22 bytes
	var length = 0		# 2 bytes
	var finetune = 0	# 1 byte
	var volume = 64		# 1 byte
	var loop_start = 0	# 2 bytes
	var loop_end = 0	# 2 bytes

	var sample:AudioStreamSample
	var data = []  #Sample data in "native" Generator format (PoolVector2Array)

	var c5_freq = 8363  #Frequency of sample, in Hz, of C-5

	#Requires 30 byte array
	func init_header(bytes : PoolByteArray):
		var i = 0
		
		#Get name.
		name = ""
		for j in range(22):
			if bytes[j] == 0:  break
			name += char(bytes[j])
		i = 21
		
		#Get sample length.  First byte overwritten by tracker. 
		length = (bytes[22] << 8) | bytes[23]
		length = length << 1
		
		#Get finetune signed nybble (-8..7).  1/8 semitone 
		finetune = bytes[24] & 0xF
		c5_freq = global.FINETUNE_FREQ[finetune]
		
		#Get volume
		volume = bytes[25]

		#Get loop.  End of loop must be > 1 to qualify as looping.
		loop_start = (bytes[26] << 8) | bytes[27]
		loop_end = (bytes[28] << 8) | bytes[29]
		
		#Value is in words so we have to shift left. Loop_end is an offset value..
		loop_start = loop_start << 1
		loop_end = loop_end << 1
		loop_end += loop_start
	
	func is_looping():
		if loop_end <= 2:  return false
		if loop_end-1 > loop_start:  return true
		return false
		
	#Converts the sample data to a format AudioStreamGenerator understands.
	func cache_generator_data():
		if sample == null:
			printerr("Sample is empty!  No data!")
		
		#Note that this func only works on 8-bit mono samples.
		#If the loading format changes, the good boy data should be processed FIRST,
		#And then we can generate a preview sample AudioStreamSample later.
		data.clear()
		for b in sample.data:
			var a = ((b+128)%256) /128.0  -1
			data.append(Vector2(a, a))
		
		#Now that we have sample data size, make sure the loop end doesn't exceed it
		loop_end = min(loop_end, data.size())

	#Get sample at position
	func sample_at_position(pos):
		if sample == null or data.empty():  return Vector2.ZERO
		
		if !is_looping():
			if pos > data.size():
				return Vector2.ZERO
			else:
				return data[pos] #* (volume/64.0)
		else:  #Looping
			if pos >= loop_end:
				return data[ (int(pos) - loop_start) % loop_end ] #* (volume/64.0)
			else:
				return data[int(pos)] #* (volume/64.0)


#Storage note
class Note:
	var instrument = 0
	var period = 0 
	var volume = 64
	var effect = ""
	var parameter = 0
	
	func get_info():
		return "%s %s %s%s" % [period2note(), instrument, 
								effect, global.int2hex(parameter)]

	func period2note():
		if period == 0: return "..."
		var pos = global.period_table.find(period) 
#		var pos = global.period_table.bsearch_custom(period, self, "comparator") 
		if pos == -1:
			#Finetune value has messed with this, figure out a better way
			#To determine the closest note instead.  TODO
			return "???"  
		else:
			var octave = pos / 12
			return global.note_string[pos%12] + String(octave)

	func comparator(a,b):
		return !(a<b)

	#Gets the native sampling Hz rate needed to produce iteration value
	const CLOCK_SPEED = 7093789.2   #m68k running at 7.09 MHz (PAL)
	func get_sample_rate():
		if period == 0:  return 0
		return CLOCK_SPEED / float(period*2)


#Playback channel
class Channel:
	var pos = 0  #Carat position in sample
	var lastNote:Note
	var note:Note
	var currentSample:Sample  #Sample associated with current note
		
	var iteration_amt = 0  #How much to iterate position on next sampling

	#Working note / active tick modifiers
	var volume_mod = 0
	var pitch_mod = 1.0
	var working_effect = "0"
	var working_parameter = 0
	

	func nextSample(playback_rate=44100.0, peek=false):
		if !note or !currentSample:  return Vector2.ZERO
		if peek:  return currentSample.sample_at_position(pos)

		var nextIteration = note.get_sample_rate() / playback_rate
		if nextIteration != 0:  
			iteration_amt = nextIteration
		pos += iteration_amt
		
		#TODO:  modify period based on effect changes
		var samp = currentSample.sample_at_position(pos)
		#Modify volume.
		if working_effect == "C":  #Set volume
			samp *= (volume_mod/64.0)
		elif working_effect == "A":  #Volume slide.
			samp *= clamp(note.volume + volume_mod, 0, 64) / 64.0
		#TODO:  implement effects 5/6
		else:  #Not under a volume command.  Use default volume.
			samp * (note.volume/64.0)
			
		return samp
	

#Module data storage and retrival routines
class Module:
	var isReady = false
	#Storage banks
	var sampleBank = []
	var patterns = []
	var channels = [Channel.new(), Channel.new(), Channel.new(), Channel.new()]

	
	#Mod info
	var title = ""
	var positions_total = 0  #Total number of positions in orderlist
	var unique_patterns = 0  #Total number of unique patterns
	var orders = []  #Pattern order.  128 elements.
	

	#Playback system
	var waited = 0 #Number of frames processed this loop.
	var frames = 0 #Playback offset in frames.
	var playback_rate = 44100.0 setget set_playback_rate 

	func set_playback_rate(val):
		playback_rate = val
		samples_per_tick = int(playback_rate * ticktime)


	#Timer system
	#Default speed is 6 ticks/row 125bpm. This corresponds to 384 ticks per pattern,
	#and a tick is 1/50 of a second in most cases, presuming PAL vblank timing.
	#Standard pattern is about 7.68s in PAL and 6.4s in NTSC.
	
	# SampleRate = (CLOCK_SPEED / period)
	const CLOCK_SPEED = 7093789.2   #m68k running at 7.09 MHz (PAL)
	

	var speed = 6  #Ticks per row
	var bpm = 125  #Beats per minute (kinda)
	var ticktime =   0.02 / (bpm / 125.0)  #Adjust tick time by bpm.
	var samples_per_tick = int(playback_rate * ticktime)

	var position = 0
	var row = 0
	var tick = 0


	func reset():
		frames = 0 
		position = 0
		row = 0
		tick = 0
		channels = [Channel.new(), Channel.new(), Channel.new(), Channel.new()]
		
	func load_module(path):
		position = 0
		row = 0
		tick = 0
		
		var f = File.new()
		f.open(path, File.READ)
		f.endian_swap = true  #Amiga is big-endian
		
		#Module header "M.K." located here at byte 1080. Check it to know the format.
		f.seek(1080)
		var header = "" 
		for i in 4:
			header += char(f.get_8())
		if not is_supported_format(header):
			#Technically, if we detect pattern data in this chunk,
			#It might be a 15-sample mod.....
			OS.alert("Unsupported module format!")
			return
		
	
		f.seek(0)
		
		#Get module title.
		title = ""   
		var t = f.get_buffer(20)
		#Why no String(PoolByteArray) work?  hulk smash
		for c in t:
			if c == 0:  break
			title += char(c)
	
		#Read 30 samples here (1..31).  TODO: Detect if 15-sample mod only somehow..
		sampleBank.clear()
		for i in range(30):
			var samp = Sample.new()
			samp.init_header(f.get_buffer(30))
			sampleBank.append(samp)
	
	
		f.seek(950)
	
		#Get number of positions in the orderlist.
		positions_total = f.get_8()
		
		#Unused byte.  In NoiseTracker this indicates the restart position.
		f.get_8()
		
		#Get ordered positions (pattern order).  128 bytes here.
		orders.clear()
		unique_patterns = 0
		for i in range(128):
			if i < positions_total:
				var order = f.get_8()
				orders.append(order)
				
				#Determine number of unique patterns.
				if (order+1) > unique_patterns:   unique_patterns=order+1
				
			else:
				f.get_8()  #Dump blank order
	
		#We already read the header.  Skip to pattern data.
		f.get_32()
	
		#Read pattern data.
		patterns.clear()
#		print(unique_patterns)
		for i in range(unique_patterns):
			#Un-lazy storage method.  1kb data total per pattern
			var pattern = []  #64 rows
			for row in range(64):
				var rowdata = []  #4 channels!
				for chn in range(4):
					#32-bits of data here per note chunk.
					#Due to the way an extra 15 instruments were hacked in,
					#The instrument's 8-bit value is spread over 2 separate nybbles.
					#Labeled wwww/yyyy below, the MSB(upper bits) is wwww.
	
					#7654-3210 7654-3210 7654-3210 7654-3210
					#wwww xxxx xxxx-xxxx yyyy zzzz zzzz-zzzz
					
					#  x (12 bits):  Note period
					#  z (12 bits):  Note effect
	
					var note_w = f.get_32()  #Remember, endian swap is on
					var note = Note.new()
					
					#Instruments start at 01. Empty is 0.
					#To retrieve the proper sample bank, subtract 1.
					note.instrument  = (note_w>>12) & 0xF
					note.instrument |= (note_w>>24) & 0xF0
					
					note.parameter = note_w & 0xFF
					note.effect = global.int2hex((note_w >>8) & 0xF)
					note.period = (note_w>>16) & 0xFFF
	
					#TODO: reinterpret Cxx as vol command and convert to linear float
					#TODO: lookup note in period table and assign it.
					rowdata.append(note)
				pattern.append(rowdata)
			patterns.append(pattern)


		#Get sample data.  In MODs this is always 8-bit.  s:Sample
		for s in sampleBank:
			var samp = AudioStreamSample.new()
			samp.format = AudioStreamSample.FORMAT_8_BITS
			samp.mix_rate = s.c5_freq
			#0-65535 words (Amiga:  16bits per word?)
			samp.data = f.get_buffer(s.length)  
	
			s.sample = samp 			#Assign sample to bank
			s.cache_generator_data()	#Create native sample data for generator
	
		f.close()
		isReady = true



	#Fills an audio buffer with the number of frames requested.
	func fill_buffer(nFrames):
		#Determine how many secs have elapsed in buffer time.
		var elapsed_time = nFrames / playback_rate

		if frames == 0:  #First tick.  Make sure there's data here
			process_tick(0)
#			for i in 4:
#				var note = patterns[orders[0]] [0] [i]
#				channels[i].note = note
#				channels[i].currentSample = sampleBank[note.instrument-1]

		frames += nFrames

		#Now that potential ticks are processed, get samples.
		var arr = []  #PoolVector2Array of final output buffer
		
		while nFrames > 0:
			#Have we filled enough frames for the clock to tick over?
			if waited >= samples_per_tick:
				waited -= samples_per_tick
				process_tick()  #Process next tick.


			var framedata = Vector2.ZERO
#			for i in channels.size():
			for i in channels.size():
				var next_sample= channels[i].nextSample(playback_rate)/channels.size()
				#Mix the 4 channels together.
				framedata += next_sample 
			arr.append(framedata)
			nFrames -=1
			waited +=1
			

		
		return arr


	#Changes the channel information for the next tick when retreiving info for buf
	func process_tick(jump_forward=1):
		tick += jump_forward
		if tick >= speed:
			#Next row.
			row +=1
			tick = 0
		if row >= 64:
			#Next pattern in order.
			position +=1
			row = 0
		if position >= positions_total:
			position = 0
			frames = 0

		for i in 4:   #Process each channel
			var note = patterns[orders[position]] [row] [i]
			if tick ==0:  #Process next row.
				var last = channels[i].note
				channels[i].lastNote = last
				channels[i].note = note

#				if note != channels[i].lastNote:  #Stop if still on the same tick
				if last and note.period > 0 and note.period != last.period:
					#Period value changed.  Reset channel carat position.
					channels[i].pos = 0
					channels[i].iteration_amt = 0
				if note.instrument > 0:  #Change samples, the instrument changed.
					channels[i].currentSample = sampleBank[note.instrument-1]
					if note.period != 0:
						channels[i].pos = 0
						channels[i].iteration_amt = 0
					else:
						channels[i].volume_mod = 0
#			if note.instrument > 0 and note.period == 0:  channels[i].volume_mod = 0
					
			process_tick_fx(i)  #Happens every tick.

	#Called during a tick process, this updates a channel's working data.
	func process_tick_fx(channel):
		var ch = channels[channel]
		var note = ch.note
		
		if !note:  return
		
		#TODO:  determine if the effect param continues from a previous row.
		if note.effect != "0":  ch.working_effect = note.effect
		
		match note.effect:
			"0":  #Arpeggio
				if note.parameter == 0:  #No effect.  Reset working effect.
					ch.working_effect = "0"
					ch.volume_mod = 0
					#Note: Don't reset params here.  Only the working effect.

				else: #Do arpeggio.
					pass #TODO
					
			"1":  #Portamento up
				pass
			"2":  #Portamento down
				pass
			"3":  #Tone Portamento
				pass
			"4":  #Vibrato
				pass
			"5":  #Portamento + Volume Slide
				pass
			"6":  #Vibrato + Volume Slide
				pass
			"7":  #Tremolo
				pass
			"8":  #ProTracker:  Unused.  /  FastTracker:  Set Pan
				pass
			"9":  #Set sample offset
				var x = note.parameter >> 4
				var y = note.parameter & 0xF
				note.pos = x*4096 + y*256

			"A":  #Volume slide
				var x = note.parameter >> 4
				var y = note.parameter & 0xF
				if x>0:   
					#If both columns are nonzero, it's technically ndefined behavior.
					#modformat.txt says we should slide up anyway.
					ch.volume_mod = max(64, ch.volume_mod + x)
				elif y>0:
					ch.volume_mod = min(0, ch.volume_mod - y)

				
				pass
			"B":  #Position jump
				var x = note.parameter >> 4
				var y = note.parameter & 0xF
				
				#TODO:  Queue jump for next time tick == 0
				
			"C":  #Set volume
				ch.volume_mod = note.parameter
			"D":  #Pattern Break
				#TODO:  Queue jump for next time tick == 0
				pass

			"E": #The big ugly mess.  TODO
				pass
				
				
			"F":  #Set Speed / Set Tempo
				if note.parameter == 0:  pass
				elif note.parameter < 32:
					speed = note.parameter
				else:
					bpm = note.parameter
					ticktime =   0.02 / (bpm / 125.0)  #Adjust tick time by bpm.
					samples_per_tick = int(playback_rate * ticktime)
							

	#Check if this is a 4 channel module.
	func is_supported_format(header_string):
		var validHeaders = ["M.K.", "M!K!", "4CHN", "FLT4"]
		for o in validHeaders:
			if header_string == o:  return true
		return false


#Transport and storage class for arbitrary tick position in a mod.
class ModPosition:
	var position = 0  #Pattern position in order
	var row = 0
	var tick = 0
