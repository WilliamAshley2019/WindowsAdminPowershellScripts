Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Runtime.InteropServices

# Win32 API: Simulate mouse click
$signature = @"
[DllImport("user32.dll")]
public static extern bool SetForegroundWindow(IntPtr hWnd);

[DllImport("user32.dll")]
public static extern bool GetCursorPos(out POINT lpPoint);

[DllImport("user32.dll")]
[return: MarshalAs(UnmanagedType.Bool)]
public static extern bool SetCursorPos(int X, int Y);

[DllImport("user32.dll")]
public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);

public struct POINT {
    public int X;
    public int Y;
}
"@

Add-Type -MemberDefinition $signature -Namespace WinAPI -Name User32

# Constants for mouse click
$MOUSEEVENTF_LEFTDOWN = 0x02
$MOUSEEVENTF_LEFTUP   = 0x04

# Function to simulate click at system tray clock area
function Show-Calendar {
    # Find bottom-right area (approx where clock is)
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $clockX = $bounds.Width - 5
    $clockY = $bounds.Height - 5

    # Move cursor to clock and simulate click
    [WinAPI.User32]::SetCursorPos($clockX, $clockY)
    Start-Sleep -Milliseconds 200
    [WinAPI.User32]::mouse_event($MOUSEEVENTF_LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    [WinAPI.User32]::mouse_event($MOUSEEVENTF_LEFTUP,   0, 0, 0, [UIntPtr]::Zero)
}

# Get screen info
$screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$widgetWidth  = 120
$widgetHeight = 40
$posX = $screen.Left + $screen.Width - $widgetWidth - 10
$posY = $screen.Top + $screen.Height - $widgetHeight - 10

# Create the widget form
$form = New-Object Windows.Forms.Form
$form.Text = ""
$form.Size = New-Object Drawing.Size($widgetWidth, $widgetHeight)
$form.FormBorderStyle = 'None'
$form.TopMost = $true
$form.StartPosition = 'Manual'
$form.Location = New-Object Drawing.Point($posX, $posY)
$form.BackColor = [System.Drawing.Color]::Black
$form.ForeColor = [System.Drawing.Color]::White
$form.Opacity = 0.85

# Day label
$label = New-Object Windows.Forms.Label
$label.Font = New-Object Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$label.AutoSize = $true
$label.Location = New-Object Drawing.Point(10, 8)
$label.BackColor = 'Transparent'
$form.Controls.Add($label)

# Timer updates
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 1000
$timer.Add_Tick({
    $label.Text = (Get-Date).ToString("dddd")
})
$timer.Start()

# Hover to open calendar
$form.Add_MouseEnter({
    $form.BackColor = [System.Drawing.Color]::DarkSlateGray
    $form.Opacity = 1.0
    Show-Calendar
})
$form.Add_MouseLeave({
    $form.BackColor = [System.Drawing.Color]::Black
    $form.Opacity = 0.85
})

# Show form
$form.ShowDialog()
