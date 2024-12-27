#!/usr/bin/env python3.9

from tkinter import Toplevel 
from tkinter import messagebox
import tkinter as tk
import keyboard
from roku import Roku
roku = Roku('192.168.8.124')
r = tk.Tk()
#r.geometry("250x768")
r.geometry("160x120")
search_var=tk.StringVar()
currentString=""
currentStringLen = 0
def handle_key_press(event):
    if event.keysym == 'Left':
        roku.left()
    if event.keysym == 'Right':
        roku.right()
    if event.keysym == 'Up':
        roku.up()
    if event.keysym == 'Down':
        roku.down()
    if event.keysym == 'Return':
        roku.select()
    if event.keysym == 'Space':
        roku.play()
    if event.keysym == 'BackSpace':
        roku.power()
    if event.keysym == 'Shift_R':
        roku.play()
    if event.char == '=':
        roku.volume_up()
    if event.char == '-':
        roku.volume_down()
    if event.char == '0':
        roku.volume_mute()
    if event.char == '/':
        roku.back()
    if event.char == '5':
        roku.home()
    if event.char == '1':
        roku.input_hdmi1()
    if event.char == '2':
        roku.input_hdmi2()
    if event.char == '3':
        roku.input_hdmi3()
    if event.char == '4':
        roku.input_hdmi4()
    if event.char == '`':
        roku.power()

def handle_text_entry(event):
    global currentStringLen
    if event.keysym == 'Return':
        currentString = event.widget.get()
        #print("the length of this string is: ")
        #print(len(currentString))
        currentStringLen = len(currentString)
        roku.literal(currentString)
    if event.keysym == 'Escape':
        #print("There is no escaping Cornholio!")
        event.widget.delete(0, 'end')
        clear_text_entry()

def clear_text_entry():
    global currentStringLen
    for i in range(0, currentStringLen+2):
        roku.backspace()
    currentStringLen = 0

def open_popup():
   top = Toplevel()
   pFrame = tk.Frame(top)
   top.title("Enter Search")
   pFrame.bind("<KeyPress>", handle_key_press)
   searchEntry = tk.Entry(top)
   searchEntry.bind("<KeyPress>", handle_text_entry)
   sub_btn=tk.Button(top, text = 'Clear', command = clear_text_entry)
   searchEntry.pack()
   sub_btn.pack()
   pFrame.focus_set()
   pFrame.pack()
   top.mainloop()
def display_layout():
    messagebox.showinfo("Layout", "BUTTON LAYOUT:\n================\nUp [Up Arrow] \nLeft [Left Arrow]\n Right [Right Arrow]\nDown [Down Arrow]\n Back [/]\nPlay/Pause [Right Shift]\nSelect [Enter/Return]\nPower [Del/Backspace]\nVolume Up [=]\nVolume Down[-]\nMute Toggle [0]\n===============\nCLICK OK TO RESUME CONTROL\n", parent = r, default = "ok")

r.title('ROKU REMOTE')
frame = tk.Frame(r)
frame.bind("<KeyPress>", handle_key_press)
buttonQuote = tk.Button(r, text='Search', width=5, command=open_popup)
buttonLayout = tk.Button(r, text='HELP', width=5, command=display_layout)
buttonQuote.pack()
buttonLayout.pack()

frame.focus_set() # Ensure the frame has focus to receive key events
frame.pack()
#r.title('ROKU REMOTE')
r.mainloop()
