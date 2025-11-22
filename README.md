# AoE2Mouse_Camera_Drag
AutohotkeyScript for Age Of Empires 2: Definitive Edition that allows Camera Dragging Controls


The script demonstrates how to hook into AoE2 memory to read/write directly to camera offsets to enable modern camera drag behaviour with a mouse. Most commonly "Scroll Drag" or "Scroll Camera Drag" as opposed to edge pan. 
At thie time this was published AoE2 had no proper camera drag support. 

This version still doesnt feel as good as modern native RTS camera drag such as WC3 but contains several features to smooth out experience:
-Scaling with camera zoom (needs tuning)
-Controllable drag speed in X and Y directions
-Deadzone to avoid stairstepping behaviour when trying to drag camera straight up/down or sideways
-Smoothing behaviour can be overtuned to enable snappier/overshooting instead of smooth/floaty.


Usage:
Run script as administrator with autohotkey 

