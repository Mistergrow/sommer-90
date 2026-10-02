class_name ScenePatchRenderer
extends RefCounted
## Zustandsfreier Renderer fuer BYTEWERK. Die App besitzt Workflow und Daten;
## diese Klasse besitzt ausschließlich die aufwendigen Preview-/Matrix-Paints.

const C_PANEL:=Color8(31,43,62);const C_INK:=Color8(224,232,232);const C_DIM:=Color8(126,144,156)
const C_BLUE:=Color8(72,184,220);const C_GOLD:=Color8(248,196,72);const C_GREEN:=Color8(92,220,138)
const C_RED:=Color8(235,92,90)

static func draw_patch(o, font:Font)->void:
	var rows:Array=o.call("_puzzle_rows")
	var revision_name:=str(o.get("_puzzle").get("revision_name","P-8 MATRIX"))
	o.text(font,revision_name,20,68,14,C_GOLD)
	var rule_text:="Regel: "+str(o.get("_puzzle").get("rule","Pruefsummen, Spiegelung und Paritaet in Einklang bringen."))
	o.text(font,rule_text.left(88),132,68,8,C_DIM)
	var results:Array=o.get("_row_results")
	var row_gap:=34.0 if rows.size()<=6 else 27.0
	for i in rows.size():
		var row:Dictionary=rows[i];var y:=86.0+i*row_gap;var result_ok=null
		if i<results.size():
			var rr=results[i];result_ok=rr.get("ok",false)if typeof(rr)==TYPE_DICTIONARY else bool(rr)
		var edge:=C_GREEN if result_ok==true else(C_RED if result_ok==false else Color8(67,88,105))
		o.rect(20,y,438,29,C_PANEL);o.rect_line(20,y,438,29,edge)
		var phase_label:=str(row.get("label","SIG-%02d"%(i+1))).replace("P-8 PHASENZEILE","PHASE")
		o.text(font,phase_label.left(12),29,y+19,8,C_BLUE)
		var cells:Array=o.call("_row_cells",row);var mutable:=int(row.get("mutable_index",row.get("mutable",2)))
		for c in cells.size():
			var x:=126.0+c*42.0;var val:=str(o.call("_answer_for_row",row,i))if c==mutable else str(cells[c]).to_upper()
			if val=="":val="??"
			o.rect(x,y+4,34,21,Color8(13,22,32)if c!=mutable else Color8(73,51,19));o.rect_line(x,y+4,34,21,C_GOLD if c==mutable else Color8(54,72,88));o.text_c(font,val.left(3),x,x+34,y+19,8,C_GOLD if c==mutable else C_INK)
	var hint_rows:int=o.get("_hint_rows")
	if hint_rows>0 and not rows.is_empty():
		var hinted:Dictionary=rows[clampi(hint_rows-1,0,rows.size()-1)];o.text(font,"HINWEIS %d: %s"%[hint_rows,str(hinted.get("hint","Vergleiche die Randpaare.")).left(73)],20,306,7,C_GOLD)
	o.text(font,"Gold = Fantasiefeld · WERT schaltet ausschließlich erlaubte Kandidaten.",20,320,8,C_DIM)
	if bool(o.get("_verified")):
		var result:Dictionary=o.get("_patch_result");var stability:=float(result.get("stability",0.0));if stability<=1.0:stability*=100.0
		o.text(font,"MATRIX STABIL  ·  Score %d  ·  Stabilität %d%%"%[int(result.get("score",0)),roundi(stability)],20,348,9,C_GREEN)

static func draw_intro_preview(o,font:Font,area:Rect2)->void:
	var colors:Array=o.call("_active_colors");var effects:Array=o.get("_selected_effects");var anim:float=o.get("_anim_t")
	o.rect(area.position.x,area.position.y,area.size.x,area.size.y,colors[0]);o.rect_line(area.position.x,area.position.y,area.size.x,area.size.y,C_GOLD)
	if effects.has("copperbars"):
		for i in 9:
			var yy:=area.position.y+22+i*5;var ci:=1+posmod(i+floori(anim*5.0),colors.size()-1);o.rect(area.position.x+2,yy,area.size.x-4,4,colors[ci].darkened(.12))
	if effects.has("starfield"):
		for i in 26:
			var sx:=area.position.x+5+posmod(i*47+floori(anim*(8+i%4)),int(area.size.x-10));var sy:=area.position.y+7+posmod(i*29,int(area.size.y-42));var s:=2.0 if i%5==0 else 1.0;o.rect(sx,sy,s,s,colors[4])
	if effects.has("vectorgrid"):
		var horizon:=area.position.y+128
		for i in 7:var bx:=area.position.x+i*area.size.x/6.0;o.draw_line(o._V(area.get_center().x,horizon),o._V(bx,area.end.y-30),colors[2],maxf(1.0,o._sx()))
		for i in 6:var gy:=horizon+pow(float(i)/5.0,1.7)*74.0;o.draw_line(o._V(area.position.x+2,gy),o._V(area.end.x-2,gy),colors[2],maxf(1.0,o._sy()))
	if effects.has("bobs"):
		for i in 5:var bx:=area.position.x+30+i*40;var by:=area.position.y+144+sin(anim*2.1+i)*22;o.draw_circle(o._V(bx,by),5.0*minf(o._sx(),o._sy()),colors[2+i%3])
	var logo_y:=area.position.y+79
	if effects.has("rasterlogo"):
		for i in 4:o.text_c(font,"BYTEWERK",area.position.x+2+sin(anim*2.0+i)*2.0,area.end.x-2,logo_y+i*2,17,colors[1+i%(colors.size()-1)])
	o.text_c(font,"BYTEWERK",area.position.x+4,area.end.x+4,logo_y+3,17,Color(0,0,0,.7));o.text_c(font,"BYTEWERK",area.position.x+2,area.end.x-2,logo_y,17,colors[4]);o.text_c(font,str(o.call("_presenting_name"))+" PRESENTS",area.position.x+2,area.end.x-2,logo_y+22,8,colors[3])
	var cy:=area.position.y+120.0;var credits:Dictionary=o.get("_selected_credits")
	for candidate in o.call("_optional_credit_candidates"):
		if credits.has(o.call("_credit_key",candidate)):
			o.text_c(font,"%s · %s"%[o.call("_credit_handle",candidate),candidate.get("role","HELP")],area.position.x+2,area.end.x-2,cy,7,colors[4]);cy+=10
	var scroll:String=o.call("_scroller_text");var span:=maxf(1.0,area.size.x+scroll.length()*5.5);var scroll_x:=area.end.x-fmod(anim*34.0,span);var scroll_y:=area.end.y-12.0
	if effects.has("sinescroll")or effects.has("sine_scroller"):scroll_y+=sin(anim*3.0)*4.0
	o.draw_string(font,o._V(scroll_x,scroll_y),scroll,HORIZONTAL_ALIGNMENT_LEFT,-1,maxi(5,int(7*o._sy())),colors[3])

static func draw_testboot(o,font:Font)->void:
	o.call("_draw_panel",Rect2(62,70,516,252));o.text_c(font,"REPRODUZIERBARKEITSTEST",62,578,96,15,C_GOLD);o.text_c(font,"Drei simulierte Startbedingungen — kein zufälliger Fehlschlag, kein Zeitdruck.",62,578,116,8,C_DIM)
	var boot_log:Array=o.get("_boot_log");var running:bool=o.get("_boot_running");var step:int=o.get("_boot_step")
	for i in 3:
		var y:=144.0+i*42.0;var done:=i<boot_log.size();var active:=running and i==step;o.rect(94,y,452,30,Color8(25,58,48)if done else(Color8(49,45,24)if active else C_PANEL));o.rect_line(94,y,452,30,C_GREEN if done else(C_GOLD if active else Color8(65,82,96)));o.text(font,"%d"%(i+1),106,y+20,10,C_GOLD if active else C_INK)
		var waiting:String=["KALTSTART","SPEICHERWECHSEL","NEUSTART"][i];o.text(font,boot_log[i]if done else waiting+(" · LÄUFT …"if active else" · wartet"),138,y+20,9,C_GREEN if done else(C_GOLD if active else C_DIM))
	if bool(o.get("_boot_complete")):o.text_c(font,"✓ 3/3 GRÜN",62,578,288,12,C_GREEN)

static func draw_complete(o,font:Font)->void:
	o.call("_draw_panel",Rect2(88,82,464,250));o.call("_draw_disk_icon",Vector2(120,112),C_GREEN);o.text(font,"SCENE-RELEASE FERTIG",222,132,16,C_GREEN)
	var disk=o.get("disk");o.text(font,disk.display_name()if disk!=null else"Release",222,156,10,C_INK);var result:Dictionary=o.get("_final_result");o.text(font,"SERIAL  %s"%str(result.get("serial","P-8/READY")),222,178,9,C_GOLD)
	o.text(font,"Die Arbeitsdiskette trägt jetzt das persistierte Intro.",120,226,9,C_INK);o.text(font,"INTRO STARTEN zeigt die echte Vorschau. Erst [ Spiel starten ]",120,246,9,C_DIM);o.text(font,"markiert das Intro als gesehen und macht die Release-Kopie verkaufsbereit.",120,264,9,C_DIM)

static func draw_status(o,font:Font)->void:
	o.rect(4,368,632,27,Color8(8,13,21));o.rect_line(4,368,632,27,Color8(52,76,92));o.text(font,("P-8 › "+str(o.get("_status"))).left(104),12,386,8,C_GREEN if not bool(o.get("_blocked"))else C_RED)

static func draw_panel(o,area:Rect2)->void:
	o.button3d(area,C_PANEL,true);o.rect_line(area.position.x,area.position.y,area.size.x,area.size.y,Color8(76,104,121))

static func draw_disk_icon(o,at:Vector2,glow:Color)->void:
	o.rect(at.x,at.y,68,78,Color8(54,62,72));o.rect_line(at.x,at.y,68,78,glow,2.0);o.rect(at.x+14,at.y+8,40,24,Color8(14,21,29));o.rect(at.x+23,at.y+45,31,25,Color8(190,190,178));o.rect(at.x+30,at.y+49,10,17,Color8(32,35,38));o.rect(at.x+8,at.y+38,52,3,glow)
