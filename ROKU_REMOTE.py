#!/usr/bin/env python3

from tkinter import Toplevel, messagebox, ttk, Canvas
import tkinter as tk
from roku import Roku

# Global variables
roku = None
discovered_devices = {}
selected_device_ip = None

r = tk.Tk()
r.geometry("260x210")
r.title('ROKU REMOTE')

def open_device_scanner():
    """Open a modal popup window to scan and select a Roku device."""
    global discovered_devices, selected_device_ip, roku
    
    top = Toplevel(r)
    top.title("Select Roku Device")
    top.geometry("280x160")
    top.transient(r)
    top.grab_set()  # Make window modal
    
    lbl = tk.Label(top, text="Discovered Roku Devices:", font=("Arial", 10, "bold"))
    lbl.pack(pady=(10, 5))
    
    device_var = tk.StringVar()
    device_combo = ttk.Combobox(top, textvariable=device_var, state="readonly", width=32)
    device_combo.pack(pady=5)
    
    def perform_scan():
        device_combo['values'] = ["Scanning network..."]
        device_combo.set("Scanning network...")
        top.update()
        
        discovered_devices.clear()
        try:
            rokus = Roku.discover(timeout=2)
            for dev in rokus:
                # Attempt to grab device info/name if available
                try:
                    info = dev.device_info
                    name = info.user_device_name or info.model_name or "Roku Device"
                except Exception:
                    name = "Roku Device"
                
                label_str = f"{name} ({dev.host})"
                discovered_devices[label_str] = dev
        except Exception as e:
            print("Discovery error:", e)
            
        if discovered_devices:
            labels = list(discovered_devices.keys())
            device_combo['values'] = labels
            device_combo.current(0)
        else:
            device_combo['values'] = ["No devices found"]
            device_combo.set("No devices found")

    def on_ok():
        global roku, selected_device_ip
        selection = device_var.get()
        if selection in discovered_devices:
            dev = discovered_devices[selection]
            roku = dev
            selected_device_ip = selection
            update_status("green", f"Connected to {selection}")
        top.destroy()
        r.focus_set()

    def on_cancel():
        top.destroy()
        r.focus_set()

    btn_frame = tk.Frame(top)
    btn_frame.pack(pady=10)
    
    ok_btn = tk.Button(btn_frame, text="OK", width=8, command=on_ok, takefocus=False)
    cancel_btn = tk.Button(btn_frame, text="CANCEL", width=8, command=on_cancel, takefocus=False)
    
    ok_btn.pack(side=tk.LEFT, padx=5)
    cancel_btn.pack(side=tk.RIGHT, padx=5)
    
    # Run initial scan inside the popup
    top.after(100, perform_scan)

def update_status(color, message):
    """Update the status indicator LED color and status text message."""
    led_canvas.itemconfig(led_circle, fill=color)
    status_label.config(text=f"Status: {message}")

def handle_key_press(event):
    global roku
    if not roku:
        return
        
    if event.keysym == 'Left':
        roku.left()
    elif event.keysym == 'Right':
        roku.right()
    elif event.keysym == 'Up':
        roku.up()
    elif event.keysym == 'Down':
        roku.down()
    elif event.keysym == 'Return':
        roku.select()
    elif event.keysym == 'Space':
        roku.play()
    elif event.keysym == 'BackSpace':
        roku.power()
    elif event.keysym == 'Shift_R':
        roku.play()
    elif event.char == '=':
        roku.volume_up()
    elif event.char == '-':
        roku.volume_down()
    elif event.char == '0':
        roku.volume_mute()
    elif event.char == '/':
        roku.back()
    elif event.char == '5':
        roku.home()
    elif event.char == '1':
        roku.input_hdmi1()
    elif event.char == '2':
        roku.input_hdmi2()
    elif event.char == '3':
        roku.input_hdmi3()
    elif event.char == '4':
        roku.input_hdmi4()
    elif event.char == '`':
        roku.power()

currentStringLen = 0

def handle_text_entry(event):
    global currentStringLen, roku
    if not roku:
        return
    if event.keysym == 'Return':
        currentString = event.widget.get()
        currentStringLen = len(currentString)
        roku.literal(currentString)
    elif event.keysym == 'Escape':
        event.widget.delete(0, 'end')
        clear_text_entry()

def clear_text_entry():
    global currentStringLen, roku
    if not roku:
        return
    for i in range(0, currentStringLen + 2):
        roku.backspace()
    currentStringLen = 0

def open_popup():
    top = Toplevel(r)
    top.title("Enter Search")
    
    searchEntry = tk.Entry(top)
    searchEntry.pack(padx=10, pady=10)
    searchEntry.bind("<KeyPress>", handle_text_entry)
    
    sub_btn = tk.Button(top, text='Clear', command=clear_text_entry, takefocus=False)
    sub_btn.pack(pady=5)
    
    searchEntry.focus_set()

def display_layout():
    messagebox.showinfo(
        "Layout", 
        "BUTTON LAYOUT:\n================\nUp [Up Arrow] \nLeft [Left Arrow]\n Right [Right Arrow]\nDown [Down Arrow]\n Back [/]\nPlay/Pause [Right Shift]\nSelect [Enter/Return]\nPower     [Del/Backspace]\nVolume Up [=]\nVolume Down[-]\nMute Toggle [0]\n===============\nCLICK OK TO RESUME CONTROL\n", 
        parent=r, 
        default="ok"
    )
    r.focus_set()

# Bind keypress events globally to the root window `r`
r.bind("<KeyPress>", handle_key_press)

# Main UI Layout Elements
scan_btn = tk.Button(r, text='FIND ROKU DEVICES', width=20, command=open_device_scanner, takefocus=False)
buttonQuote = tk.Button(r, text='Search', width=20, command=open_popup, takefocus=False)
buttonLayout = tk.Button(r, text='HELP', width=20, command=display_layout, takefocus=False)

scan_btn.pack(pady=(15, 5))
buttonQuote.pack(pady=5)
buttonLayout.pack(pady=5)

# Status LED frame in bottom right corner (or anchored neatly)
status_frame = tk.Frame(r)
status_frame.pack(side=tk.BOTTOM, fill=tk.X, padx=10, pady=8)

led_canvas = Canvas(status_frame, width=16, height=16, highlightthickness=0)
led_circle = led_canvas.create_oval(2, 2, 14, 14, fill="gray", outline="black")
led_canvas.pack(side=tk.RIGHT)

status_label = tk.Label(status_frame, text="Status: None", font=("Arial", 9), anchor="e")
status_label.pack(side=tk.RIGHT, padx=5)

r.focus_set()
r.mainloop()
