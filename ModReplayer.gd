extends Control

var sampleBank = []
var sampleControls = []  #References to sample info controls

var title = ""
var positions_total = 0  #Total number of positions in orderlist
var unique_patterns = 0  #Total number of unique patterns
var patterns = []
var orders = []  #Pattern order.  128 elements.

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


func play_sample(num):
	if num >= sampleBank.size():
		printerr("SampleBank only contains %s samples. Sample not found" % sampleBank.size())
		return
	var samp = sampleBank[num]
	$SampleInfo.text = "Sample %s (%s):" % [num, samp.name]
	$SampleInfo.text +="\nlength: 		%s" % samp.length
	$SampleInfo.text +="\nfinetune:		%s" % samp.finetune
	$SampleInfo.text +="\nvolume: 		%s" % samp.volume
	$SampleInfo.text +="\nloop_start:		%s" % samp.loop_start
	$SampleInfo.text +="\nloop_end:		%s" % samp.loop_end

	$SamplePreview.stop()
	$SamplePreview.stream = samp.sample 
	$SamplePreview.play()

func _on_Open_pressed():
	$FileDialog.show_modal()
	pass # Replace with function body.


func _on_FileDialog_file_selected(path):
	load_module(path)

	$Pattern.clear()
	for i in 4:
		$Pattern.add_item("Channel %s" % (i+1), null, false)
		
	for row in patterns[0]:
		for note in row:
			$Pattern.add_item(note.get_info())



func load_module(path):
	var f = File.new()
	f.open(path, File.READ)
	f.endian_swap = true  #Amiga is big-endian
	
	#Module header "M.K." located here at byte 1080.  Check it to know the format.
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
	$lblTitle.text = title

	#Read 30 samples here (1..31).  TODO: Detect if 15-sample mod only somehow....
	sampleBank.clear()
	for i in range(30):
		var samp = Sample.new()
		samp.init_header(f.get_buffer(30))
		sampleControls[i].set_text(samp.name)
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
	print(unique_patterns)
	for i in range(unique_patterns):
#		#Each pattern is 1kb of data.  We don't care what it is yet, store it lazy
#		patterns.append(f.get_buffer(1024))

		#Un-lazy storage method
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

				#TODO: reinterpret Cxx as volume command and convert to linear float
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

		s.sample = samp

	f.close()


#Check if this is a 4 channel module.
func is_supported_format(header_string):
	var validHeaders = ["M.K.", "M!K!", "4CHN", "FLT4"]
	for o in validHeaders:
		if header_string == o:  return true
	return false




class Sample:
	# 30 bytes header
	var name = ""		# 22 bytes
	var length = 0		# 2 bytes
	var finetune = 0	# 1 byte
	var volume = 64		# 1 byte
	var loop_start = 0	# 2 bytes
	var loop_end = 0	# 2 bytes

	var sample:AudioStreamSample

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
		if pos == -1:
			#Finetune value has messed with this, figure out a better way
			#To determine the closest note instead.  TODO
			return "???"  
		else:
			var octave = pos / 12
			return global.note_string[pos%12] + String(octave)

#Playback channel
class Channel:
	var pos  #Carat position in sample
	var lastNote:Note
	var note:Note