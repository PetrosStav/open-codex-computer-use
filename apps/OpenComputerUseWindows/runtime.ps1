param(
    [Parameter(Mandatory = $true)]
    [string]$OperationPath
)

$ErrorActionPreference = "Stop"
$DefaultTextLimit = 500
$AccessibilityTreeMaxNodeCount = 1200
$AccessibilityTreeMaxDepth = 64

# Set output encoding to UTF-8 to properly handle non-ASCII characters
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Drawing

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class OCUWin32 {
    [DllImport("shcore.dll")]
    public static extern int SetProcessDpiAwareness(int awareness);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct KEYBDINPUT {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MOUSEINPUT {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Explicit)]
    public struct InputUnion {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct INPUT {
        public uint type;
        public InputUnion union;
    }

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

    [DllImport("user32.dll")]
    public static extern bool ScreenToClient(IntPtr hWnd, ref POINT point);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern bool PostMessage(IntPtr hWnd, UInt32 msg, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr SendMessage(IntPtr hWnd, UInt32 msg, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr SendMessage(IntPtr hWnd, UInt32 msg, IntPtr wParam, string lParam);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    private static INPUT KeyboardInput(ushort virtualKey, uint flags) {
        INPUT input = new INPUT();
        input.type = 1;
        input.union.ki.wVk = virtualKey;
        input.union.ki.dwFlags = flags;
        return input;
    }

    private static bool IsExtendedKey(ushort virtualKey) {
        switch (virtualKey) {
            case 0x21: // Page Up
            case 0x22: // Page Down
            case 0x23: // End
            case 0x24: // Home
            case 0x25: // Left
            case 0x26: // Up
            case 0x27: // Right
            case 0x28: // Down
            case 0x2D: // Insert
            case 0x2E: // Delete
            case 0x5B: // Left Windows
            case 0x5C: // Right Windows
                return true;
            default:
                return false;
        }
    }

    private static INPUT KeyEvent(ushort virtualKey, bool keyUp) {
        uint flags = IsExtendedKey(virtualKey) ? 1u : 0u;
        if (keyUp) {
            flags |= 2u;
        }
        return KeyboardInput(virtualKey, flags);
    }

    public static void SendKeySequence(ushort[] modifiers, ushort virtualKey) {
        INPUT[] inputs = new INPUT[modifiers.Length * 2 + 2];
        int index = 0;
        foreach (ushort modifier in modifiers) {
            inputs[index++] = KeyEvent(modifier, false);
        }
        inputs[index++] = KeyEvent(virtualKey, false);
        inputs[index++] = KeyEvent(virtualKey, true);
        for (int i = modifiers.Length - 1; i >= 0; i--) {
            inputs[index++] = KeyEvent(modifiers[i], true);
        }

        uint sent = SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(INPUT)));
        if (sent != inputs.Length) {
            throw new System.ComponentModel.Win32Exception(
                Marshal.GetLastWin32Error(),
                "SendInput sent " + sent + " of " + inputs.Length + " keyboard events"
            );
        }
    }

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetCursorPos(int x, int y);

    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int virtualKey);

    [DllImport("user32.dll")]
    public static extern IntPtr WindowFromPoint(POINT point);

    [DllImport("user32.dll")]
    public static extern IntPtr SetFocus(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern IntPtr GetAncestor(IntPtr hWnd, uint flags);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool IsWindowEnabled(IntPtr hWnd);

    [DllImport("oleacc.dll")]
    private static extern int AccessibleObjectFromWindow(
        IntPtr hWnd,
        uint objectId,
        ref Guid interfaceId,
        [MarshalAs(UnmanagedType.Interface)] out object accessible
    );

    public static object GetAccessibleClient(IntPtr hWnd) {
        Guid accessibleId = new Guid("618736e0-3c3d-11cf-810c-00aa00389b71");
        object accessible;
        int result = AccessibleObjectFromWindow(hWnd, 0xFFFFFFFC, ref accessibleId, out accessible);
        if (result != 0) {
            Marshal.ThrowExceptionForHR(result);
        }
        return accessible;
    }

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("kernel32.dll")]
    public static extern uint GetCurrentThreadId();

    [DllImport("user32.dll")]
    public static extern bool AttachThreadInput(uint attach, uint attachTo, bool value);

    public static IntPtr ResolveActionWindow(uint processId, IntPtr mainWindow) {
        IntPtr foreground = GetForegroundWindow();
        uint foregroundProcessId;
        GetWindowThreadProcessId(foreground, out foregroundProcessId);
        if (foregroundProcessId == processId && IsWindowVisible(foreground) && IsWindowEnabled(foreground)) {
            return foreground;
        }

        if (mainWindow != IntPtr.Zero && IsWindowVisible(mainWindow) && IsWindowEnabled(mainWindow)) {
            return mainWindow;
        }

        IntPtr candidate = IntPtr.Zero;
        EnumWindows(delegate(IntPtr window, IntPtr ignored) {
            uint windowProcessId;
            GetWindowThreadProcessId(window, out windowProcessId);
            if (windowProcessId == processId && IsWindowVisible(window) && IsWindowEnabled(window)) {
                candidate = window;
                return false;
            }
            return true;
        }, IntPtr.Zero);
        return candidate != IntPtr.Zero ? candidate : mainWindow;
    }

    public static bool ActivateWindow(IntPtr target) {
        IntPtr foreground = GetForegroundWindow();
        if (foreground == target) {
            return true;
        }

        uint ignored;
        uint currentThread = GetCurrentThreadId();
        uint foregroundThread = GetWindowThreadProcessId(foreground, out ignored);
        uint targetThread = GetWindowThreadProcessId(target, out ignored);
        bool foregroundAttached = foregroundThread != 0 && foregroundThread != currentThread &&
            AttachThreadInput(currentThread, foregroundThread, true);
        bool targetAttached = targetThread != 0 && targetThread != currentThread && targetThread != foregroundThread &&
            AttachThreadInput(currentThread, targetThread, true);
        try {
            return SetForegroundWindow(target);
        }
        finally {
            if (targetAttached) {
                AttachThreadInput(currentThread, targetThread, false);
            }
            if (foregroundAttached) {
                AttachThreadInput(currentThread, foregroundThread, false);
            }
        }
    }

    public static bool FocusWindowAtPoint(IntPtr target, int x, int y) {
        POINT point = new POINT();
        point.X = x;
        point.Y = y;
        IntPtr child = WindowFromPoint(point);
        uint targetProcess;
        uint childProcess;
        GetWindowThreadProcessId(target, out targetProcess);
        uint childThread = GetWindowThreadProcessId(child, out childProcess);
        if (child == IntPtr.Zero || childProcess != targetProcess || GetAncestor(child, 2) != target) {
            return false;
        }

        uint currentThread = GetCurrentThreadId();
        bool attached = childThread != 0 && childThread != currentThread &&
            AttachThreadInput(currentThread, childThread, true);
        try {
            SetFocus(child);
            return true;
        }
        finally {
            if (attached) {
                AttachThreadInput(currentThread, childThread, false);
            }
        }
    }

    public static bool IsPointOverWindow(IntPtr target, int x, int y) {
        POINT point = new POINT();
        point.X = x;
        point.Y = y;
        IntPtr child = WindowFromPoint(point);
        return child != IntPtr.Zero && GetAncestor(child, 2) == target;
    }

    private static void SendMouseButton(uint flags) {
        INPUT input = new INPUT();
        input.type = 0;
        input.union.mi.dwFlags = flags;
        INPUT[] inputs = new INPUT[] { input };
        uint sent = SendInput(1, inputs, Marshal.SizeOf(typeof(INPUT)));
        if (sent != 1) {
            throw new System.ComponentModel.Win32Exception(
                Marshal.GetLastWin32Error(),
                "SendInput mouse event failed"
            );
        }
    }

    private static void SendMouseWheelInput(uint flags, int data) {
        INPUT input = new INPUT();
        input.type = 0;
        input.union.mi.mouseData = unchecked((uint)data);
        input.union.mi.dwFlags = flags;
        INPUT[] inputs = new INPUT[] { input };
        uint sent = SendInput(1, inputs, Marshal.SizeOf(typeof(INPUT)));
        if (sent != 1) {
            throw new System.ComponentModel.Win32Exception(
                Marshal.GetLastWin32Error(),
                "SendInput mouse wheel event failed"
            );
        }
    }

    private static void GetMouseButton(string button, out uint down, out uint up, out int virtualKey) {
        switch (button) {
            case "right":
                down = 0x0008;
                up = 0x0010;
                virtualKey = 0x02;
                return;
            case "middle":
                down = 0x0020;
                up = 0x0040;
                virtualKey = 0x04;
                return;
            default:
                down = 0x0002;
                up = 0x0004;
                virtualKey = 0x01;
                return;
        }
    }

    private static void MovePointerToTarget(IntPtr target, int x, int y, int settleMilliseconds) {
        if (!SetCursorPos(x, y)) {
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "SetCursorPos failed");
        }
        System.Threading.Thread.Sleep(settleMilliseconds);
        if (GetForegroundWindow() != target || !IsPointOverWindow(target, x, y)) {
            throw new InvalidOperationException("Target app lost foreground or no longer covers the pointer target");
        }
    }

    public static void SendMouseMove(IntPtr target, int x, int y) {
        MovePointerToTarget(target, x, y, 150);
    }

    public static void SendMouseClick(IntPtr target, int x, int y, string button, int count) {
        uint down;
        uint up;
        int virtualKey;
        GetMouseButton(button, out down, out up, out virtualKey);
        MovePointerToTarget(target, x, y, 150);

        for (int click = 0; click < count; click++) {
            if (GetForegroundWindow() != target || !IsPointOverWindow(target, x, y)) {
                throw new InvalidOperationException("Target app lost foreground or no longer covers the click point");
            }
            bool buttonDown = false;
            try {
                SendMouseButton(down);
                buttonDown = true;
                System.Threading.Thread.Sleep(35);
                if ((GetAsyncKeyState(virtualKey) & 0x8000) == 0) {
                    throw new InvalidOperationException("Injected mouse button did not enter the down state");
                }
            }
            finally {
                if (buttonDown) {
                    SendMouseButton(up);
                }
            }
            System.Threading.Thread.Sleep(75);
            if (click + 1 < count) {
                System.Threading.Thread.Sleep(75);
            }
        }
    }

    public static void SendMouseWheel(IntPtr target, int x, int y, int delta, bool horizontal) {
        MovePointerToTarget(target, x, y, 150);
        SendMouseWheelInput(horizontal ? 0x1000u : 0x0800u, delta);
    }

    public static void SendMouseDrag(IntPtr target, int[] coordinates, string button) {
        if (coordinates == null || coordinates.Length < 4 || coordinates.Length % 2 != 0) {
            throw new ArgumentException("Drag requires at least two coordinate pairs", "coordinates");
        }

        uint down;
        uint up;
        int virtualKey;
        GetMouseButton(button, out down, out up, out virtualKey);
        MovePointerToTarget(target, coordinates[0], coordinates[1], 150);

        double totalDistance = 0;
        for (int point = 2; point < coordinates.Length; point += 2) {
            double dx = coordinates[point] - coordinates[point - 2];
            double dy = coordinates[point + 1] - coordinates[point - 1];
            totalDistance += Math.Sqrt(dx * dx + dy * dy);
        }
        int totalSteps = Math.Min(600, Math.Max(12, (int)Math.Ceiling(totalDistance / 8.0)));

        bool buttonDown = false;
        try {
            SendMouseButton(down);
            buttonDown = true;
            System.Threading.Thread.Sleep(75);
            if ((GetAsyncKeyState(virtualKey) & 0x8000) == 0) {
                throw new InvalidOperationException("Injected mouse button did not enter the down state");
            }
            for (int point = 2; point < coordinates.Length; point += 2) {
                int fromX = coordinates[point - 2];
                int fromY = coordinates[point - 1];
                int toX = coordinates[point];
                int toY = coordinates[point + 1];
                double dx = toX - fromX;
                double dy = toY - fromY;
                double segmentDistance = Math.Sqrt(dx * dx + dy * dy);
                int segmentSteps = totalDistance == 0 ? 1 :
                    Math.Max(1, (int)Math.Round(totalSteps * segmentDistance / totalDistance));

                for (int step = 1; step <= segmentSteps; step++) {
                    if (GetForegroundWindow() != target) {
                        throw new InvalidOperationException("Target app lost foreground during drag");
                    }
                    int currentX = (int)Math.Round(fromX + dx * step / segmentSteps);
                    int currentY = (int)Math.Round(fromY + dy * step / segmentSteps);
                    if (!SetCursorPos(currentX, currentY)) {
                        throw new System.ComponentModel.Win32Exception(
                            Marshal.GetLastWin32Error(),
                            "SetCursorPos failed during drag"
                        );
                    }
                    System.Threading.Thread.Sleep(8);
                }
            }
        }
        finally {
            if (buttonDown) {
                SendMouseButton(up);
                System.Threading.Thread.Sleep(75);
            }
        }
    }
}
"@

# UI Automation exposes physical screen coordinates. Keep Win32 hit testing and
# cursor placement in that same coordinate space on mixed-DPI desktops.
[void][OCUWin32]::SetProcessDpiAwareness(2)

$WM_SETTEXT = 0x000C
$WM_MOUSEMOVE = 0x0200
$WM_LBUTTONDOWN = 0x0201
$WM_LBUTTONUP = 0x0202
$WM_RBUTTONDOWN = 0x0204
$WM_RBUTTONUP = 0x0205
$WM_MBUTTONDOWN = 0x0207
$WM_MBUTTONUP = 0x0208
$WM_MOUSEWHEEL = 0x020A
$WM_MOUSEHWHEEL = 0x020E
$WM_KEYDOWN = 0x0100
$WM_KEYUP = 0x0101
$WM_CHAR = 0x0102
$EM_SETSEL = 0x00B1
$EM_REPLACESEL = 0x00C2
$BM_CLICK = 0x00F5

function Test-EnvFlagEnabled([string]$name) {
    $value = [Environment]::GetEnvironmentVariable($name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $false
    }
    $normalized = $value.Trim().ToLowerInvariant()
    return @("1", "true", "yes", "on") -contains $normalized
}

function New-Frame($x, $y, $width, $height) {
    if ($width -lt 0 -or $height -lt 0) {
        return $null
    }
    [pscustomobject]@{
        x = [double]$x
        y = [double]$y
        width = [double]$width
        height = [double]$height
    }
}

function ConvertTo-LParam([int]$x, [int]$y) {
    $packed = (($y -band 0xffff) -shl 16) -bor ($x -band 0xffff)
    [IntPtr]$packed
}

function ConvertTo-WheelWParam([int]$delta) {
    $packed = (($delta -band 0xffff) -shl 16)
    [IntPtr]$packed
}

function Get-WindowRectFrame([IntPtr]$hwnd) {
    $rect = New-Object OCUWin32+RECT
    if ([OCUWin32]::GetWindowRect($hwnd, [ref]$rect)) {
        return New-Frame $rect.Left $rect.Top ($rect.Right - $rect.Left) ($rect.Bottom - $rect.Top)
    }
    return $null
}

function Get-ElementFrame($element, $windowBounds) {
    try {
        $rect = $element.Current.BoundingRectangle
        if ($rect.IsEmpty -or $rect.Width -le 0 -or $rect.Height -le 0) {
            return $null
        }
        if ($null -ne $windowBounds) {
            return New-Frame ($rect.X - $windowBounds.x) ($rect.Y - $windowBounds.y) $rect.Width $rect.Height
        }
        return New-Frame $rect.X $rect.Y $rect.Width $rect.Height
    } catch {
        return $null
    }
}

function Get-ScreenPoint($localFrame, $windowBounds) {
    if ($null -eq $localFrame -or $null -eq $windowBounds) {
        return $null
    }
    [pscustomobject]@{
        x = [int][math]::Round($windowBounds.x + $localFrame.x + ($localFrame.width / 2))
        y = [int][math]::Round($windowBounds.y + $localFrame.y + ($localFrame.height / 2))
    }
}

function Send-MouseClick([IntPtr]$hwnd, [int]$screenX, [int]$screenY, [string]$button, [int]$count) {
    $point = New-Object OCUWin32+POINT
    $point.X = $screenX
    $point.Y = $screenY
    [void][OCUWin32]::ScreenToClient($hwnd, [ref]$point)
    $lParam = ConvertTo-LParam $point.X $point.Y

    $down = $WM_LBUTTONDOWN
    $up = $WM_LBUTTONUP
    $downFlag = 0x0001
    if ($button -eq "right") {
        $down = $WM_RBUTTONDOWN
        $up = $WM_RBUTTONUP
        $downFlag = 0x0002
    } elseif ($button -eq "middle") {
        $down = $WM_MBUTTONDOWN
        $up = $WM_MBUTTONUP
        $downFlag = 0x0010
    }

    $repeat = [math]::Max(1, $count)
    for ($i = 0; $i -lt $repeat; $i++) {
        [void][OCUWin32]::PostMessage($hwnd, $WM_MOUSEMOVE, [IntPtr]::Zero, $lParam)
        [void][OCUWin32]::PostMessage($hwnd, $down, [IntPtr]$downFlag, $lParam)
        Start-Sleep -Milliseconds 35
        [void][OCUWin32]::PostMessage($hwnd, $up, [IntPtr]::Zero, $lParam)
        Start-Sleep -Milliseconds 50
    }
}

function Get-OperationScreenPoint($operation, $windowBounds) {
    if ($null -ne $operation.element -and $null -ne $operation.element.frame) {
        return Get-ScreenPoint $operation.element.frame $windowBounds
    }
    if ($null -eq $operation.x -or $null -eq $operation.y -or $null -eq $windowBounds) {
        throw "Pointer action requires element_index or x/y coordinates from the latest snapshot"
    }
    [pscustomobject]@{
        x = [int][math]::Round($windowBounds.x + [double]$operation.x)
        y = [int][math]::Round($windowBounds.y + [double]$operation.y)
    }
}

function Initialize-PhysicalPointerTarget([IntPtr]$hwnd, [int]$screenX, [int]$screenY, [bool]$focusChild) {
    if ($hwnd -eq [IntPtr]::Zero) {
        throw "Cannot use physical pointer input because the target app has no top-level window"
    }
    if ([OCUWin32]::IsIconic($hwnd)) {
        [void][OCUWin32]::ShowWindow($hwnd, 9)
    }
    if (-not [OCUWin32]::ActivateWindow($hwnd)) {
        throw "Cannot use physical pointer input because Windows refused to activate the target app"
    }
    Start-Sleep -Milliseconds 250
    if ([OCUWin32]::GetForegroundWindow() -ne $hwnd) {
        throw "Cannot use physical pointer input because the target app did not remain in the foreground"
    }
    if (-not [OCUWin32]::IsPointOverWindow($hwnd, $screenX, $screenY)) {
        throw "Cannot use physical pointer input because the requested point is not over the target app"
    }
    if ($focusChild -and -not [OCUWin32]::FocusWindowAtPoint($hwnd, $screenX, $screenY)) {
        throw "Cannot focus the target child window for physical pointer input"
    }
}

function Send-PhysicalClick([IntPtr]$hwnd, [int]$screenX, [int]$screenY, [string]$button, [int]$count) {
    Initialize-PhysicalPointerTarget $hwnd $screenX $screenY $true
    [OCUWin32]::SendMouseClick($hwnd, $screenX, $screenY, $button, $count)
}

function Send-Hover([IntPtr]$hwnd, [int]$screenX, [int]$screenY) {
    Initialize-PhysicalPointerTarget $hwnd $screenX $screenY $false
    [OCUWin32]::SendMouseMove($hwnd, $screenX, $screenY)
}

function Send-Drag([IntPtr]$hwnd, [int[]]$coordinates, [string]$button) {
    if ($null -eq $coordinates -or $coordinates.Length -lt 4) {
        throw "Cannot drag without at least two coordinate pairs"
    }
    Initialize-PhysicalPointerTarget $hwnd $coordinates[0] $coordinates[1] $true
    [OCUWin32]::SendMouseDrag($hwnd, $coordinates, $button)
}

function Send-PhysicalScroll([IntPtr]$hwnd, [int]$screenX, [int]$screenY, [string]$direction, [double]$pages) {
    Initialize-PhysicalPointerTarget $hwnd $screenX $screenY $false
    $delta = [int][math]::Round(120 * $pages)
    $horizontal = $direction -eq "left" -or $direction -eq "right"
    if ($direction -eq "down" -or $direction -eq "left") {
        $delta = -1 * $delta
    }
    [OCUWin32]::SendMouseWheel($hwnd, $screenX, $screenY, $delta, $horizontal)
}

function Send-Text([IntPtr]$hwnd, [string]$text) {
    foreach ($char in $text.ToCharArray()) {
        [void][OCUWin32]::PostMessage($hwnd, $WM_CHAR, [IntPtr][int][char]$char, [IntPtr]::Zero)
        Start-Sleep -Milliseconds 8
    }
}

function Send-TextToEditHandle([IntPtr]$hwnd, [string]$text, $element) {
    if ($hwnd -eq [IntPtr]::Zero) {
        return $false
    }

    try {
        $hasKeyboardFocus = $false
        try { $hasKeyboardFocus = [bool]$element.Current.HasKeyboardFocus } catch {}
        if (-not $hasKeyboardFocus) {
            [void][OCUWin32]::SendMessage($hwnd, $EM_SETSEL, [IntPtr](-1), [IntPtr](-1))
        }
        [void][OCUWin32]::SendMessage($hwnd, $EM_REPLACESEL, [IntPtr]1, $text)
        return $true
    } catch {
    }

    try {
        $current = ""
        if ($null -ne $element) {
            $current = Get-ElementValue $element
        }
        [void][OCUWin32]::SendMessage($hwnd, $WM_SETTEXT, [IntPtr]::Zero, ($current + $text))
        return $true
    } catch {
        return $false
    }
}

function Get-VirtualKey([string]$key) {
    $normalized = $key.ToLowerInvariant()
    $map = @{
        "return" = 0x0D; "enter" = 0x0D; "tab" = 0x09; "escape" = 0x1B; "esc" = 0x1B
        "backspace" = 0x08; "back_space" = 0x08; "delete" = 0x2E; "space" = 0x20
        "left" = 0x25; "up" = 0x26; "right" = 0x27; "down" = 0x28
        "home" = 0x24; "end" = 0x23; "page_up" = 0x21; "prior" = 0x21; "page_down" = 0x22; "next" = 0x22
        "insert" = 0x2D
        "ctrl" = 0x11; "control" = 0x11; "shift" = 0x10; "alt" = 0x12
        "win" = 0x5B; "super" = 0x5B; "cmd" = 0x5B
    }
    if ($map.ContainsKey($normalized)) {
        return $map[$normalized]
    }
    if ($normalized -match "^f([1-9]|1[0-2])$") {
        return 0x70 + [int]$Matches[1] - 1
    }
    if ($normalized -match "^kp_([0-9])$") {
        return 0x60 + [int]$Matches[1]
    }
    if ($normalized.Length -eq 1) {
        $code = [int][char]$normalized.ToUpperInvariant()[0]
        if (($code -ge 0x30 -and $code -le 0x39) -or ($code -ge 0x41 -and $code -le 0x5A)) {
            return $code
        }
    }
    throw "Unsupported key: $key"
}

function Send-Key([IntPtr]$hwnd, [string]$key) {
    $parts = $key -split "\+"
    $main = $parts[$parts.Length - 1]
    $modifiers = @()
    for ($i = 0; $i -lt $parts.Length - 1; $i++) {
        switch ($parts[$i].ToLowerInvariant()) {
            "ctrl" { $modifiers += 0x11 }
            "control" { $modifiers += 0x11 }
            "shift" { $modifiers += 0x10 }
            "alt" { $modifiers += 0x12 }
            "super" { $modifiers += 0x5B }
            "win" { $modifiers += 0x5B }
            "cmd" { $modifiers += 0x5B }
            default { throw "Unsupported modifier: $($parts[$i])" }
        }
    }

    if ($hwnd -eq [IntPtr]::Zero) {
        throw "Cannot press a key because the target app has no top-level window"
    }

    if ([OCUWin32]::IsIconic($hwnd)) {
        [void][OCUWin32]::ShowWindow($hwnd, 9)
    }
    if (-not [OCUWin32]::ActivateWindow($hwnd)) {
        throw "Cannot press a key because Windows refused to activate the target app"
    }
    Start-Sleep -Milliseconds 300
    if ([OCUWin32]::GetForegroundWindow() -ne $hwnd) {
        throw "Cannot press a key because the target app did not remain in the foreground"
    }

    [OCUWin32]::SendKeySequence([System.UInt16[]]$modifiers, [System.UInt16](Get-VirtualKey $main))
}

function Resolve-App([string]$query) {
    $normalized = $query.Trim()
    $processQuery = $normalized
    if ($processQuery.EndsWith(".exe", [System.StringComparison]::OrdinalIgnoreCase)) {
        $processQuery = $processQuery.Substring(0, $processQuery.Length - 4)
    }
    $processes = @(Get-Process | Where-Object { $_.MainWindowHandle -ne 0 })
    $pidValue = 0
    if ([int]::TryParse($normalized, [ref]$pidValue)) {
        $match = $processes | Where-Object { $_.Id -eq $pidValue } | Select-Object -First 1
        if ($null -ne $match) {
            return $match
        }
    }

    $match = $processes | Where-Object {
        $_.ProcessName -ieq $processQuery -or
        "$($_.ProcessName).exe" -ieq $normalized -or
        $_.MainWindowTitle -ieq $normalized -or
        $_.MainWindowTitle -ilike "*$normalized*"
    } | Select-Object -First 1
    if ($null -ne $match) {
        return $match
    }

    if (Test-EnvFlagEnabled "OPEN_COMPUTER_USE_WINDOWS_ALLOW_APP_LAUNCH") {
        try {
            $started = Start-Process -FilePath $normalized -PassThru
            for ($i = 0; $i -lt 20; $i++) {
                Start-Sleep -Milliseconds 250
                $candidate = Get-Process -Id $started.Id -ErrorAction SilentlyContinue
                if ($null -ne $candidate -and $candidate.MainWindowHandle -ne 0) {
                    return $candidate
                }
            }
        } catch {
        }
    }

    throw "appNotFound(`"$query`")"
}

function Get-MainElement($process) {
    $hwnd = [OCUWin32]::ResolveActionWindow([uint32]$process.Id, [IntPtr]$process.MainWindowHandle)
    if ($hwnd -ne [IntPtr]::Zero) {
        return [Windows.Automation.AutomationElement]::FromHandle($hwnd)
    }
    $condition = New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::ProcessIdProperty), $process.Id
    $children = [Windows.Automation.AutomationElement]::RootElement.FindAll([Windows.Automation.TreeScope]::Children, $condition)
    if ($children.Count -gt 0) {
        return $children.Item(0)
    }
    throw "No top-level UI Automation window is available for $($process.ProcessName). Run the Windows runtime in the signed-in desktop session."
}

function Get-WindowBounds($process, $element) {
    $hwnd = Get-NativeWindowHandle $element
    if ($hwnd -eq [IntPtr]::Zero) {
        $hwnd = [IntPtr]$process.MainWindowHandle
    }
    if ($hwnd -ne [IntPtr]::Zero) {
        $fromWin32 = Get-WindowRectFrame $hwnd
        if ($null -ne $fromWin32) {
            return $fromWin32
        }
    }
    try {
        $rect = $element.Current.BoundingRectangle
        if (-not $rect.IsEmpty -and $rect.Width -gt 0 -and $rect.Height -gt 0) {
            return New-Frame $rect.X $rect.Y $rect.Width $rect.Height
        }
    } catch {
    }
    return $null
}

function Test-NativeButtonClass([string]$className) {
    return @("Button", "CCPushButton") -contains $className
}

function Get-PatternNames($element) {
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($pattern in $element.GetSupportedPatterns()) {
        $programmatic = $pattern.ProgrammaticName
        if ($programmatic -like "InvokePatternIdentifiers.Pattern") { $names.Add("Invoke") }
        elseif ($programmatic -like "TogglePatternIdentifiers.Pattern") { $names.Add("Toggle") }
        elseif ($programmatic -like "SelectionItemPatternIdentifiers.Pattern") { $names.Add("Select") }
        elseif ($programmatic -like "ExpandCollapsePatternIdentifiers.Pattern") {
            try {
                $state = $element.GetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern).Current.ExpandCollapseState
                if ($state -eq [Windows.Automation.ExpandCollapseState]::Collapsed) { $names.Add("Expand") }
                elseif ($state -eq [Windows.Automation.ExpandCollapseState]::Expanded) { $names.Add("Collapse") }
            } catch {
                $names.Add("Expand")
                $names.Add("Collapse")
            }
        }
        elseif ($programmatic -like "ScrollItemPatternIdentifiers.Pattern") { $names.Add("ScrollIntoView") }
        elseif ($programmatic -like "ScrollPatternIdentifiers.Pattern") { $names.Add("Scroll") }
        elseif ($programmatic -like "ValuePatternIdentifiers.Pattern") { $names.Add("SetValue") }
    }
    if ((Test-NativeButtonClass (Get-ElementString $element "ClassName")) -and (Get-ElementInt64 $element "NativeWindowHandle") -gt 0) {
        $names.Add("Invoke")
    }
    if ($names.Count -gt 0) {
        return @($names | Select-Object -Unique)
    }
    return @()
}

function Get-ElementString($element, [string]$propertyName) {
    try {
        $value = $element.Current.$propertyName
        if ($null -eq $value) {
            return ""
        }
        return [string]$value
    } catch {
        return ""
    }
}

function Get-ElementInt64($element, [string]$propertyName) {
    try {
        return [int64]$element.Current.$propertyName
    } catch {
        return 0
    }
}

function Get-ElementControlTypeName($element) {
    try {
        $controlType = $element.Current.ControlType
        if ($null -eq $controlType) {
            return ""
        }
        return [string]$controlType.ProgrammaticName
    } catch {
        return ""
    }
}

function Resolve-TextLimit($Value) {
    if ($null -eq $Value) {
        return $script:DefaultTextLimit
    }
    if ($Value -is [string] -and $Value.Trim().ToLowerInvariant() -eq "max") {
        return $null
    }
    if ($Value -is [bool]) {
        return $script:DefaultTextLimit
    }
    try {
        $integer = [int]$Value
        if ($integer -gt 0) {
            return $integer
        }
    } catch {
    }
    return $script:DefaultTextLimit
}

function Limit-Text([string]$Text, $TextLimit = $script:DefaultTextLimit) {
    if ($null -eq $Text) {
        return ""
    }
    if ($null -eq $TextLimit) {
        return $Text
    }
    $effectiveTextLimit = [int]$TextLimit
    if ($Text.Length -gt $effectiveTextLimit) {
        return $Text.Substring(0, $effectiveTextLimit) + "..."
    }
    return $Text
}

function Get-ElementValue($element, $TextLimit = $script:DefaultTextLimit) {
    try {
        $valuePattern = $element.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern)
        $value = $valuePattern.Current.Value
        if ($null -eq $value) {
            return ""
        }
        $text = [string]$value
        return Limit-Text $text $TextLimit
    } catch {
        return ""
    }
}

function Get-ElementRecord($element, [int]$index, $windowBounds, $TextLimit = $script:DefaultTextLimit) {
    $frame = Get-ElementFrame $element $windowBounds
    $runtimeId = @()
    try { $runtimeId = @($element.GetRuntimeId()) } catch {}
    $className = Get-ElementString $element "ClassName"
    $localizedControlType = Get-ElementString $element "LocalizedControlType"
    $nativeWindowHandle = Get-ElementInt64 $element "NativeWindowHandle"
    if ((Test-NativeButtonClass $className) -and $nativeWindowHandle -gt 0 -and $localizedControlType -ieq "pane") {
        $localizedControlType = "button"
    }
    [pscustomobject]@{
        index = $index
        runtimeId = $runtimeId
        automationId = Get-ElementString $element "AutomationId"
        name = Limit-Text (Get-ElementString $element "Name") $TextLimit
        controlType = Get-ElementControlTypeName $element
        localizedControlType = $localizedControlType
        className = $className
        value = Get-ElementValue $element $TextLimit
        nativeWindowHandle = $nativeWindowHandle
        frame = $frame
        actions = @(Get-PatternNames $element)
    }
}

function Get-MsaaNavigationChildren($element, $windowBounds) {
    if ((Get-ElementString $element "ClassName") -ine "SysTreeView32") {
        return @()
    }
    $hwnd = Get-NativeWindowHandle $element
    if ($hwnd -eq [IntPtr]::Zero) {
        return @()
    }

    try {
        $accessible = [OCUWin32]::GetAccessibleClient($hwnd)
        $childCount = [int]$accessible.accChildCount
        $navigationBounds = $element.Current.BoundingRectangle
    } catch {
        return @()
    }

    $items = New-Object System.Collections.Generic.List[object]
    for ($childId = 1; $childId -le $childCount; $childId++) {
        try {
            $name = [string]$accessible.accName($childId)
            if ([string]::IsNullOrWhiteSpace($name)) {
                continue
            }
            $left = 0
            $top = 0
            $width = 0
            $height = 0
            $accessible.accLocation([ref]$left, [ref]$top, [ref]$width, [ref]$height, $childId)
            if ($width -le 0 -or $height -le 0) {
                continue
            }
            if ($left + $width -le $navigationBounds.Left -or $left -ge $navigationBounds.Right -or
                $top + $height -le $navigationBounds.Top -or $top -ge $navigationBounds.Bottom) {
                continue
            }
            $frame = if ($null -eq $windowBounds) {
                New-Frame $left $top $width $height
            } else {
                New-Frame ($left - $windowBounds.x) ($top - $windowBounds.y) $width $height
            }
            $items.Add([pscustomobject]@{
                childId = $childId
                name = ($name -replace "\s+\(pinned\)$", "")
                hwnd = [int64]$hwnd
                frame = $frame
            })
        } catch {
        }
    }
    return $items.ToArray()
}

function Get-ElementTitle($record) {
    if (-not [string]::IsNullOrWhiteSpace($record.name)) {
        return $record.name
    }
    if (-not [string]::IsNullOrWhiteSpace($record.automationId)) {
        return "ID: $($record.automationId)"
    }
    return ""
}

function Render-Tree($element, $windowBounds, $TextLimit = $script:DefaultTextLimit, [int]$MaxTreeNodes = $script:AccessibilityTreeMaxNodeCount, [int]$MaxTreeDepth = $script:AccessibilityTreeMaxDepth) {
    $records = New-Object System.Collections.Generic.List[object]
    $lines = New-Object System.Collections.Generic.List[string]
    $visited = New-Object System.Collections.Generic.HashSet[string]
    $nextIndex = 0
    $effectiveMaxTreeNodes = if ($MaxTreeNodes -gt 0) { $MaxTreeNodes } else { $script:AccessibilityTreeMaxNodeCount }
    $effectiveMaxTreeDepth = if ($MaxTreeDepth -gt 0) { $MaxTreeDepth } else { $script:AccessibilityTreeMaxDepth }

    function Visit-MsaaNavigationChildren($node, [int]$depth) {
        if ($script:nextIndex -ge $script:MaxTreeNodes -or $depth -gt $script:MaxTreeDepth) {
            return
        }
        foreach ($child in (Get-MsaaNavigationChildren $node $script:windowBounds)) {
            if ($script:nextIndex -ge $script:MaxTreeNodes) {
                return
            }
            $index = $script:nextIndex
            $script:nextIndex++
            $record = [pscustomobject]@{
                index = $index
                runtimeId = @()
                automationId = "msaa:$($child.hwnd):$($child.childId)"
                name = Limit-Text $child.name $TextLimit
                controlType = "ControlType.TreeItem"
                localizedControlType = "tree item"
                className = "MSAA:SysTreeView32"
                value = ""
                nativeWindowHandle = $child.hwnd
                frame = $child.frame
                actions = @("Invoke")
            }
            $script:records.Add($record)
            $frameSegment = ""
            if ($null -ne $record.frame) {
                $frameSegment = " Frame: {{x: {0}, y: {1}, width: {2}, height: {3}}}" -f [int][math]::Round($record.frame.x), [int][math]::Round($record.frame.y), [int][math]::Round($record.frame.width), [int][math]::Round($record.frame.height)
            }
            $script:lines.Add(("`t" * ($depth + 1)) + "$index tree item $($record.name) Secondary Actions: Invoke$frameSegment")
        }
    }

    function Visit($node, [int]$depth) {
        if ($script:nextIndex -ge $script:MaxTreeNodes -or $depth -gt $script:MaxTreeDepth) {
            return
        }
        $runtime = ""
        try { $runtime = (@($node.GetRuntimeId()) -join ".") } catch { $runtime = [guid]::NewGuid().ToString() }
        if (-not $script:visited.Add($runtime)) {
            return
        }

        $index = $script:nextIndex
        $script:nextIndex++
        $record = Get-ElementRecord $node $index $script:windowBounds $TextLimit
        $script:records.Add($record)

        $role = $record.localizedControlType
        if ([string]::IsNullOrWhiteSpace($role)) {
            $role = $record.controlType
        }
        $title = Get-ElementTitle $record
        $actionsSegment = ""
        if ($record.actions.Count -gt 0) {
            $actionsSegment = " Secondary Actions: " + ($record.actions -join ", ")
        }
        $valueSegment = ""
        if (-not [string]::IsNullOrWhiteSpace($record.value) -and $record.value -ne $title) {
            $safeValue = (($record.value -replace "`r", "\\r") -replace "`n", "\\n")
            $valueSegment = " Value: $safeValue"
        }
        $frameSegment = ""
        if ($null -ne $record.frame) {
            $frameSegment = " Frame: {{x: {0}, y: {1}, width: {2}, height: {3}}}" -f [int][math]::Round($record.frame.x), [int][math]::Round($record.frame.y), [int][math]::Round($record.frame.width), [int][math]::Round($record.frame.height)
        }
        $script:lines.Add(("`t" * ($depth + 1)) + "$index $role $title$valueSegment$actionsSegment$frameSegment")

        try {
            $children = $node.FindAll([Windows.Automation.TreeScope]::Children, [Windows.Automation.Condition]::TrueCondition)
            for ($i = 0; $i -lt $children.Count; $i++) {
                Visit $children.Item($i) ($depth + 1)
            }
        } catch {
        }
        Visit-MsaaNavigationChildren $node ($depth + 1)
    }

    $script:records = $records
    $script:lines = $lines
    $script:visited = $visited
    $script:nextIndex = $nextIndex
    $script:windowBounds = $windowBounds
    $script:MaxTreeNodes = $effectiveMaxTreeNodes
    $script:MaxTreeDepth = $effectiveMaxTreeDepth
    Visit $element 0

    [pscustomobject]@{
        records = $records.ToArray()
        lines = $lines.ToArray()
    }
}

function Capture-WindowPngBase64($bounds) {
    if ($null -eq $bounds -or $bounds.width -le 0 -or $bounds.height -le 0) {
        return $null
    }
    try {
        $bitmap = New-Object System.Drawing.Bitmap ([int][math]::Round($bounds.width)), ([int][math]::Round($bounds.height))
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.CopyFromScreen([int][math]::Round($bounds.x), [int][math]::Round($bounds.y), 0, 0, $bitmap.Size)
        $stream = New-Object System.IO.MemoryStream
        $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
        $graphics.Dispose()
        $bitmap.Dispose()
        $bytes = $stream.ToArray()
        $stream.Dispose()
        return [Convert]::ToBase64String($bytes)
    } catch {
        return $null
    }
}

function Get-FocusedSummary($processId, $TextLimit = $script:DefaultTextLimit) {
    try {
        $focused = [Windows.Automation.AutomationElement]::FocusedElement
        if ($null -ne $focused -and $focused.Current.ProcessId -eq $processId) {
            $role = $focused.Current.LocalizedControlType
            $name = Limit-Text $focused.Current.Name $TextLimit
            if ([string]::IsNullOrWhiteSpace($name)) {
                return $role
            }
            return "$role $name"
        }
    } catch {
    }
    return $null
}

function Get-SelectedText($processId, $TextLimit = $script:DefaultTextLimit) {
    try {
        $focused = [Windows.Automation.AutomationElement]::FocusedElement
        if ($null -eq $focused -or $focused.Current.ProcessId -ne $processId) {
            return $null
        }
        $textPattern = $focused.GetCurrentPattern([Windows.Automation.TextPattern]::Pattern)
        $selection = $textPattern.GetSelection()
        if ($selection.Count -gt 0) {
            $maxLength = if ($null -eq $TextLimit) { -1 } else { [int]$TextLimit + 1 }
            return Limit-Text ($selection.Item(0).GetText($maxLength)) $TextLimit
        }
    } catch {
    }
    return $null
}

function Build-Snapshot([string]$query, $TextLimit = $script:DefaultTextLimit, [int]$MaxTreeNodes = $script:AccessibilityTreeMaxNodeCount, [int]$MaxTreeDepth = $script:AccessibilityTreeMaxDepth) {
    $process = Resolve-App $query
    $element = Get-MainElement $process
    $bounds = Get-WindowBounds $process $element
    $rendered = Render-Tree $element $bounds $TextLimit $MaxTreeNodes $MaxTreeDepth
    $screenshot = Capture-WindowPngBase64 $bounds

    # A shortcut can create a modal window while the initial tree is rendering.
    $latestElement = Get-MainElement $process
    if ((Get-NativeWindowHandle $latestElement) -ne (Get-NativeWindowHandle $element)) {
        $element = $latestElement
        $bounds = Get-WindowBounds $process $element
        $rendered = Render-Tree $element $bounds $TextLimit $MaxTreeNodes $MaxTreeDepth
        $screenshot = Capture-WindowPngBase64 $bounds
    }
    [pscustomobject]@{
        app = [pscustomobject]@{
            name = $process.ProcessName
            bundleIdentifier = $process.ProcessName
            pid = [int]$process.Id
        }
        windowTitle = Limit-Text (Get-ElementString $element "Name") $TextLimit
        windowBounds = $bounds
        screenshotPngBase64 = $screenshot
        treeLines = @($rendered.lines)
        focusedSummary = Get-FocusedSummary $process.Id $TextLimit
        selectedText = Get-SelectedText $process.Id $TextLimit
        elements = @($rendered.records)
    }
}

function List-Apps {
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($process in (Get-Process | Where-Object { $_.MainWindowHandle -ne 0 } | Sort-Object ProcessName, Id)) {
        $title = $process.MainWindowTitle
        if ([string]::IsNullOrWhiteSpace($title)) {
            $title = "untitled"
        }
        $lines.Add(("{0} -- {1} [running, pid={2}, window={3}]" -f $process.ProcessName, $process.ProcessName, $process.Id, $title))
    }
    return ($lines -join "`n")
}

function Same-RuntimeId($left, $right) {
    if ($null -eq $left -or $null -eq $right -or $left.Count -ne $right.Count) {
        return $false
    }
    for ($i = 0; $i -lt $left.Count; $i++) {
        if ([int]$left[$i] -ne [int]$right[$i]) {
            return $false
        }
    }
    return $true
}

function Get-AllElements($root) {
    $items = New-Object System.Collections.Generic.List[object]
    $items.Add($root)
    try {
        $descendants = $root.FindAll([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.Condition]::TrueCondition)
        for ($i = 0; $i -lt $descendants.Count; $i++) {
            $items.Add($descendants.Item($i))
        }
    } catch {
    }
    return $items.ToArray()
}

function Find-Element($process, $record) {
    if ($null -eq $record) {
        return $null
    }
    $root = Get-MainElement $process
    foreach ($element in (Get-AllElements $root)) {
        try {
            if (Same-RuntimeId @($element.GetRuntimeId()) @($record.runtimeId)) {
                return $element
            }
        } catch {
        }
    }
    foreach ($element in (Get-AllElements $root)) {
        try {
            $sameAutomationId = -not [string]::IsNullOrWhiteSpace($record.automationId) -and $element.Current.AutomationId -eq $record.automationId
            $sameName = -not [string]::IsNullOrWhiteSpace($record.name) -and $element.Current.Name -eq $record.name
            $sameType = $element.Current.ControlType.ProgrammaticName -eq $record.controlType
            if (($sameAutomationId -or $sameName) -and $sameType) {
                return $element
            }
        } catch {
        }
    }
    return $null
}

function Get-CurrentPatternOrNull($element, $pattern) {
    try {
        return $element.GetCurrentPattern($pattern)
    } catch {
        return $null
    }
}

function Invoke-NativeButton($element) {
    if ($null -eq $element -or -not (Test-NativeButtonClass (Get-ElementString $element "ClassName"))) {
        return $false
    }
    try {
        if (-not $element.Current.IsEnabled) {
            return $false
        }
    } catch {
        return $false
    }
    $buttonHwnd = Get-NativeWindowHandle $element
    if ($buttonHwnd -eq [IntPtr]::Zero) {
        return $false
    }
    [void][OCUWin32]::PostMessage($buttonHwnd, $BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero)
    return $true
}

function Invoke-MsaaElement($record) {
    if ($null -eq $record -or [string]$record.automationId -notmatch "^msaa:(\d+):(\d+)$") {
        return $false
    }
    try {
        $accessible = [OCUWin32]::GetAccessibleClient([IntPtr][int64]$Matches[1])
        [void]$accessible.accDoDefaultAction([int]$Matches[2])
        return $true
    } catch {
        return $false
    }
}

function Invoke-PreferredClick($element) {
    $invoke = Get-CurrentPatternOrNull $element ([Windows.Automation.InvokePattern]::Pattern)
    if ($null -ne $invoke) {
        $invoke.Invoke()
        return $true
    }
    $selection = Get-CurrentPatternOrNull $element ([Windows.Automation.SelectionItemPattern]::Pattern)
    if ($null -ne $selection) {
        $selection.Select()
        return $true
    }
    $toggle = Get-CurrentPatternOrNull $element ([Windows.Automation.TogglePattern]::Pattern)
    if ($null -ne $toggle) {
        $toggle.Toggle()
        return $true
    }
    return Invoke-NativeButton $element
}

function Invoke-SecondaryAction($element, [string]$action) {
    switch ($action.ToLowerInvariant()) {
        "invoke" {
            $pattern = Get-CurrentPatternOrNull $element ([Windows.Automation.InvokePattern]::Pattern)
            if ($null -ne $pattern) { $pattern.Invoke(); return }
            if (Invoke-NativeButton $element) { return }
        }
        "toggle" {
            $pattern = Get-CurrentPatternOrNull $element ([Windows.Automation.TogglePattern]::Pattern)
            if ($null -ne $pattern) { $pattern.Toggle(); return }
        }
        "select" {
            $pattern = Get-CurrentPatternOrNull $element ([Windows.Automation.SelectionItemPattern]::Pattern)
            if ($null -ne $pattern) { $pattern.Select(); return }
        }
        "expand" {
            $pattern = Get-CurrentPatternOrNull $element ([Windows.Automation.ExpandCollapsePattern]::Pattern)
            if ($null -ne $pattern) { $pattern.Expand(); return }
        }
        "collapse" {
            $pattern = Get-CurrentPatternOrNull $element ([Windows.Automation.ExpandCollapsePattern]::Pattern)
            if ($null -ne $pattern) { $pattern.Collapse(); return }
        }
        "scrollintoview" {
            $pattern = Get-CurrentPatternOrNull $element ([Windows.Automation.ScrollItemPattern]::Pattern)
            if ($null -ne $pattern) { $pattern.ScrollIntoView(); return }
        }
        "setfocus" {
            if (-not (Test-EnvFlagEnabled "OPEN_COMPUTER_USE_WINDOWS_ALLOW_FOCUS_ACTIONS")) {
                throw "SetFocus is disabled by default to avoid stealing user focus; set OPEN_COMPUTER_USE_WINDOWS_ALLOW_FOCUS_ACTIONS=1 to enable it."
            }
            $element.SetFocus()
            return
        }
    }
    throw "$action is not a valid secondary action for $($operation.element.index)"
}

function Invoke-Scroll($element, [string]$direction, [double]$pages) {
    $scroll = Get-CurrentPatternOrNull $element ([Windows.Automation.ScrollPattern]::Pattern)
    if ($null -eq $scroll) {
        return $false
    }
    try {
        $horizontal = [Windows.Automation.ScrollAmount]::NoAmount
        $vertical = [Windows.Automation.ScrollAmount]::NoAmount
        if ($direction -eq "up") { $vertical = [Windows.Automation.ScrollAmount]::LargeDecrement }
        elseif ($direction -eq "down") { $vertical = [Windows.Automation.ScrollAmount]::LargeIncrement }
        elseif ($direction -eq "left") { $horizontal = [Windows.Automation.ScrollAmount]::LargeDecrement }
        elseif ($direction -eq "right") { $horizontal = [Windows.Automation.ScrollAmount]::LargeIncrement }
        $repeat = [math]::Max(1, [int][math]::Ceiling($pages))
        for ($i = 0; $i -lt $repeat; $i++) {
            $scroll.Scroll($horizontal, $vertical)
            Start-Sleep -Milliseconds 40
        }
        return $true
    } catch {
        return $false
    }
}

function Find-TextEntryElement($process) {
    try {
        $focused = [Windows.Automation.AutomationElement]::FocusedElement
        if ($null -ne $focused -and $focused.Current.ProcessId -eq $process.Id) {
            $focusedValue = Get-CurrentPatternOrNull $focused ([Windows.Automation.ValuePattern]::Pattern)
            if (($null -ne $focusedValue -and -not $focusedValue.Current.IsReadOnly) -or (Test-TextWindowHandleCandidate $process $focused)) {
                return $focused
            }
        }
    } catch {
    }

    $root = Get-MainElement $process
    foreach ($element in (Get-AllElements $root)) {
        $valuePattern = Get-CurrentPatternOrNull $element ([Windows.Automation.ValuePattern]::Pattern)
        if ($null -eq $valuePattern -or $valuePattern.Current.IsReadOnly) {
            continue
        }
        $controlType = Get-ElementControlTypeName $element
        if ($controlType -like "*Edit*" -or $controlType -like "*Document*") {
            return $element
        }
    }

    foreach ($element in (Get-AllElements $root)) {
        $valuePattern = Get-CurrentPatternOrNull $element ([Windows.Automation.ValuePattern]::Pattern)
        if ($null -ne $valuePattern -and -not $valuePattern.Current.IsReadOnly) {
            return $element
        }
    }

    return $null
}

function Get-NativeWindowHandle($element) {
    $handle = Get-ElementInt64 $element "NativeWindowHandle"
    if ($handle -le 0) {
        return [IntPtr]::Zero
    }
    return [IntPtr]$handle
}

function Get-ClickWindowHandle($element, $record, [IntPtr]$fallback) {
    if ($null -ne $element) {
        $elementHwnd = Get-NativeWindowHandle $element
        if ($elementHwnd -ne [IntPtr]::Zero) {
            return $elementHwnd
        }
    }
    if ($null -ne $record -and [int64]$record.nativeWindowHandle -gt 0) {
        return [IntPtr][int64]$record.nativeWindowHandle
    }
    return $fallback
}

function Test-TextWindowHandleCandidate($process, $element) {
    if ($null -eq $element) {
        return $false
    }
    $handle = Get-NativeWindowHandle $element
    if ($handle -eq [IntPtr]::Zero -or $handle -eq [IntPtr]$process.MainWindowHandle) {
        return $false
    }
    $controlType = Get-ElementControlTypeName $element
    $className = Get-ElementString $element "ClassName"
    return (
        $controlType -like "*Edit*" -or
        $controlType -like "*Document*" -or
        $className -like "*Edit*" -or
        $className -like "*Rich*" -or
        $className -like "*Text*"
    )
}

function Find-TextEntryWindowHandle($process, $preferredElement) {
    if (Test-TextWindowHandleCandidate $process $preferredElement) {
        return Get-NativeWindowHandle $preferredElement
    }

    $root = Get-MainElement $process
    foreach ($element in (Get-AllElements $root)) {
        if (-not (Test-TextWindowHandleCandidate $process $element)) {
            continue
        }
        $valuePattern = Get-CurrentPatternOrNull $element ([Windows.Automation.ValuePattern]::Pattern)
        if ($null -ne $valuePattern -and -not $valuePattern.Current.IsReadOnly) {
            return Get-NativeWindowHandle $element
        }
    }

    foreach ($element in (Get-AllElements $root)) {
        if (Test-TextWindowHandleCandidate $process $element) {
            return Get-NativeWindowHandle $element
        }
    }

    return [IntPtr]::Zero
}

function Invoke-TypeText($process, [string]$text) {
    $element = Find-TextEntryElement $process
    $targetHwnd = Find-TextEntryWindowHandle $process $element
    if ($targetHwnd -ne [IntPtr]::Zero -and (Send-TextToEditHandle $targetHwnd $text $element)) {
        return $true
    }

    if ($null -ne $element) {
        $valuePattern = Get-CurrentPatternOrNull $element ([Windows.Automation.ValuePattern]::Pattern)
        if ($null -ne $valuePattern -and -not $valuePattern.Current.IsReadOnly) {
            if (-not (Test-EnvFlagEnabled "OPEN_COMPUTER_USE_WINDOWS_ALLOW_UIA_TEXT_FALLBACK")) {
                throw "UIA ValuePattern text fallback is disabled by default because it may bring the target app to the foreground; set OPEN_COMPUTER_USE_WINDOWS_ALLOW_UIA_TEXT_FALLBACK=1 to enable it."
            }
            $current = ""
            try { $current = [string]$valuePattern.Current.Value } catch {}
            $valuePattern.SetValue($current + $text)
            return $true
        }
    }
    return $false
}

# Read the operation file as UTF-8 explicitly. Windows PowerShell 5.1's
# Get-Content defaults to the system ANSI code page (e.g. GBK on Chinese
# systems) for files without a BOM, which corrupts non-ASCII input such as
# Chinese text passed to set_value/type_text.
$operationJson = [System.IO.File]::ReadAllText($OperationPath, [System.Text.Encoding]::UTF8)
$operation = $operationJson | ConvertFrom-Json

try {
    if ($operation.tool -eq "list_apps") {
        $response = [pscustomobject]@{ ok = $true; text = (List-Apps) }
    } elseif ($operation.tool -eq "get_app_state") {
        $response = [pscustomobject]@{ ok = $true; snapshot = (Build-Snapshot $operation.app (Resolve-TextLimit $operation.text_limit) ([int]$operation.max_tree_nodes) ([int]$operation.max_tree_depth)) }
    } else {
        $process = Resolve-App $operation.app
        $hwnd = [OCUWin32]::ResolveActionWindow([uint32]$process.Id, [IntPtr]$process.MainWindowHandle)
        $windowBounds = $operation.windowBounds
        $element = Find-Element $process $operation.element

        switch ($operation.tool) {
            "click" {
                $clickMethod = [string]$operation.click_method
                if ([string]::IsNullOrWhiteSpace($clickMethod)) { $clickMethod = "auto" }

                if ($clickMethod -eq "accessibility") {
                    if ($operation.mouse_button -eq "right" -or $operation.mouse_button -eq "middle") {
                        throw "click_method 'accessibility' does not support mouse_button '$($operation.mouse_button)'"
                    }
                    if ($null -eq $element -and -not (Invoke-MsaaElement $operation.element)) {
                        throw "click_method 'accessibility' requires an actionable element_index"
                    }
                    if ($null -ne $element -and -not (Invoke-PreferredClick $element)) {
                        throw "click_method 'accessibility' could not click the requested element"
                    }
                } elseif ($clickMethod -eq "app_post") {
                    $point = Get-OperationScreenPoint $operation $windowBounds
                    $clickHwnd = Get-ClickWindowHandle $element $operation.element $hwnd
                    Send-MouseClick $clickHwnd $point.x $point.y $operation.mouse_button ([int]$operation.click_count)
                } elseif ($clickMethod -eq "global") {
                    $point = Get-OperationScreenPoint $operation $windowBounds
                    Send-PhysicalClick $hwnd $point.x $point.y $operation.mouse_button ([int]$operation.click_count)
                } elseif ($clickMethod -eq "sky_click") {
                    throw "click_method 'sky_click' is not supported on Windows"
                } elseif ($clickMethod -eq "auto") {
                    $handled = $false
                    try {
                        if ($operation.mouse_button -eq "left" -and [int]$operation.click_count -eq 1 -and $null -ne $element) {
                            $handled = Invoke-PreferredClick $element
                        } elseif ($operation.mouse_button -eq "left" -and [int]$operation.click_count -eq 1 -and $null -eq $element) {
                            $handled = Invoke-MsaaElement $operation.element
                        }
                    } catch {
                        $handled = $false
                    }
                    if (-not $handled) {
                        $point = Get-OperationScreenPoint $operation $windowBounds
                        Send-PhysicalClick $hwnd $point.x $point.y $operation.mouse_button ([int]$operation.click_count)
                    }
                } else {
                    throw "Invalid click_method '$clickMethod'"
                }
            }
            "hover" {
                $point = Get-OperationScreenPoint $operation $windowBounds
                Send-Hover $hwnd $point.x $point.y
            }
            "perform_secondary_action" {
                if ($null -eq $element -and $operation.action.ToLowerInvariant() -eq "invoke" -and (Invoke-MsaaElement $operation.element)) {
                    break
                }
                if ($null -eq $element) { throw "unknown element_index '$($operation.element.index)'" }
                Invoke-SecondaryAction $element $operation.action
            }
            "scroll" {
                $handled = $false
                if ($null -ne $element) {
                    $handled = Invoke-Scroll $element $operation.direction ([double]$operation.pages)
                }
                if (-not $handled) {
                    $localFrame = $operation.element.frame
                    if ($null -eq $localFrame -and $null -ne $element) {
                        $localFrame = Get-LocalFrame $element $windowBounds
                    }
                    $point = Get-ScreenPoint $localFrame $windowBounds
                    if ($null -eq $point) {
                        throw "Cannot physically scroll an element without a visible frame"
                    }
                    Send-PhysicalScroll $hwnd $point.x $point.y $operation.direction ([double]$operation.pages)
                }
            }
            "drag" {
                $coordinates = New-Object System.Collections.Generic.List[int]
                $coordinates.Add([int][math]::Round($windowBounds.x + [double]$operation.from_x))
                $coordinates.Add([int][math]::Round($windowBounds.y + [double]$operation.from_y))
                foreach ($pathPoint in @($operation.path)) {
                    $coordinates.Add([int][math]::Round($windowBounds.x + [double]$pathPoint.x))
                    $coordinates.Add([int][math]::Round($windowBounds.y + [double]$pathPoint.y))
                }
                $coordinates.Add([int][math]::Round($windowBounds.x + [double]$operation.to_x))
                $coordinates.Add([int][math]::Round($windowBounds.y + [double]$operation.to_y))
                Send-Drag $hwnd ($coordinates.ToArray()) $operation.mouse_button
            }
            "type_text" {
                if (-not (Invoke-TypeText $process $operation.text)) {
                    Send-Text $hwnd $operation.text
                }
            }
            "press_key" {
                Send-Key $hwnd $operation.key
            }
            "set_value" {
                if ($null -eq $element) { throw "unknown element_index '$($operation.element.index)'" }
                $valuePattern = Get-CurrentPatternOrNull $element ([Windows.Automation.ValuePattern]::Pattern)
                if ($null -eq $valuePattern) {
                    throw "Cannot set a value for an element that is not settable"
                }
                $valuePattern.SetValue($operation.value)
            }
            default {
                throw "unsupportedTool(`"$($operation.tool)`")"
            }
        }

        Start-Sleep -Milliseconds 300
        $response = [pscustomobject]@{ ok = $true; snapshot = (Build-Snapshot $operation.app) }
    }
} catch {
    $message = $_.Exception.Message
    if (-not [string]::IsNullOrWhiteSpace($_.ScriptStackTrace)) {
        $message = "$message at $($_.ScriptStackTrace)"
    }
    $response = [pscustomobject]@{ ok = $false; error = $message }
}

$response | ConvertTo-Json -Depth 50 -Compress
