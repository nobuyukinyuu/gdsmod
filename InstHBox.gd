extends HBoxContainer

var num = -1

func _ready():
	pass # Replace with function body.




func set_num(n):
	$lbl.text = str(n+1)
	num = n

func set_text(txt):
	$desc.text = txt

func _on_btn_pressed():
	owner.play_sample(num)
	pass # Replace with function body.
