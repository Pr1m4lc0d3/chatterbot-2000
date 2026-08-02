[Variables]

; ---------------------------------------------------------------------------
;  Appearance - matches the Mergic desktop (Quicksand, white on translucent)
; ---------------------------------------------------------------------------
TextColor=255,255,255
DimColor=255,255,255,120
FaintColor=255,255,255,60
PanelColor=0,0,0,225
AccentColor=255,255,255,90
FontName=Quicksand

; Panel size in pixels. The mouse wheel scrolls the conversation, so size is
; set here rather than by scrolling.
PanelW=380
PanelH=532
; Height reserved between the conversation and the input box for the clickable
; Sources strip. The transcript viewport is deliberately NOT reduced to pay for
; it - the panel grew instead. Three 18px pills plus the heading need 82.
SourcesH=82

; Outer border, to match the Mergic panels.
BorderColor=255,255,255,190
BorderWidth=5

; Collapsed to just the header? Toggled by clicking the DeepSeek title.
; 0 = full panel, 1 = header only. Runtime state - do not edit by hand.
Collapsed=0

; Which face is showing: 0 = chat, 1 = settings (the gear toggles it).
; HideChat / HideSettings are derived from Collapsed + View by the toggle
; actions, so every meter can just say Hidden=#HideChat# and stay simple.
View=0
HideChat=0
HideSettings=1

; Status light beside the state text. Red until a provider key is configured.
OkColor=90,220,120,255
BadColor=235,90,90,255
StatusColor=235,90,90,255

; Which of Chatty's faces is showing. Swapped by state.
ChattyFace=chatty.png
HeaderH=56
; Source pills
PillColor=255,255,255,20
PillStroke=255,255,255,70

; Per-pill style, pushed at runtime by deepseek.ps1. Transparent = empty slot.
Pill1Style=FillColor 0,0,0,0 | StrokeColor 0,0,0,0
Pill2Style=FillColor 0,0,0,0 | StrokeColor 0,0,0,0
Pill3Style=FillColor 0,0,0,0 | StrokeColor 0,0,0,0

; Font sizes
TitleSize=15
BodySize=11
SmallSize=9

; ---------------------------------------------------------------------------
;  Sources - up to three clickable search results.
;
;  These are written at runtime by deepseek.ps1 via !SetVariable, never by
;  hand. A Rainmeter String meter takes ONE mouse action for the whole meter,
;  so a link cannot live inside the transcript paragraph - each source needs
;  its own meter, and its own URL variable to click through to.
; ---------------------------------------------------------------------------
LinkColor=130,180,245,255
SourcesLabel=
Link1Text=
Link1Url=
Link2Text=
Link2Url=
Link3Text=
Link3Url=

; ---------------------------------------------------------------------------
;  Model - click the model line in the footer to cycle these.
;  Mode 0 = v4-flash fast      (reasoning off)
;  Mode 1 = v4-flash thinking  (reasoning on)
;  Mode 2 = v4-pro   thinking  (reasoning on, strongest)
; ---------------------------------------------------------------------------
ModelMode=0

; ---------------------------------------------------------------------------
;  Scroll position, in pixels. Managed by the mouse wheel - do not edit.
; ---------------------------------------------------------------------------
; Extra pixels revealed past the end of the text, so the final line can never
; sit flush against the mask edge and lose a row to rounding.
BottomPad=8

Scroll=0
ScrollStep=40

; ---------------------------------------------------------------------------
;  Settings view - written at runtime by config.ps1, never by hand.
;  Keys are shown MASKED so a screenshot or a stream never leaks one.
; ---------------------------------------------------------------------------
CfgProvider=not set
CfgBaseUrl=not set
CfgModel=not set
CfgKey=not set
CfgSearchKey=not set
Prov1Style=FillColor 255,255,255,10 | StrokeColor 255,255,255,45
Prov2Style=FillColor 255,255,255,10 | StrokeColor 255,255,255,45
Prov3Style=FillColor 255,255,255,10 | StrokeColor 255,255,255,45
Prov4Style=FillColor 255,255,255,10 | StrokeColor 255,255,255,45
Prov5Style=FillColor 255,255,255,10 | StrokeColor 255,255,255,45
; ---------------------------------------------------------------------------
;  Message bubbles (phase 2). Coordinates are INSIDE MeterViewport, whose own
;  X is 18, so 0 here means 18 on the panel. Width available is PanelW - 36.
;
;  Bubble widths are fixed rather than hugging the text: a Rainmeter String
;  meter with W set reports that W, so a shape cannot measure the real ink.
;  A fixed max-width bubble is what most chat UIs do anyway.
; ---------------------------------------------------------------------------
MsgBubbleW=240
MsgBubbleBotX=32
MsgBubbleUserX=104
MsgLeftX=44
MsgRightX=332
MsgTextW=216
MsgFaceW=22
MsgBotStyle=FillColor 255,255,255,18 | StrokeColor 255,255,255,45
MsgUserStyle=FillColor 130,180,245,38 | StrokeColor 130,180,245,90
MsgBotText=235,235,235,255
MsgUserText=255,255,255,255
StackH=0