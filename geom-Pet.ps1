<#
  geom-Pet  ·  part of the equa series (esorhizome)

  A small wireframe solid that turns slowly in a corner of the screen.
  It leans a little toward your cursor, like a dog in the same room,
  keeping an eye on you.

  Left-drag ...... move it
  Click .......... one short line in the middle, a little spin, a few hearts
  Hover .......... shows your anchor (the one thing you're doing)
  Right-click .... anchor · breathe · shape · size (a slider) · sound · rest · close

  Run:  geom-Pet.cmd   (or: powershell -STA -File geom-Pet.ps1)
  Test: powershell -STA -File geom-Pet.ps1 -Check
#>
param([switch]$Check)

$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------- data folder
$DataDir = Join-Path $env:APPDATA 'geom-Pet'
if (-not $env:APPDATA) { $DataDir = Join-Path ([IO.Path]::GetTempPath()) 'geom-Pet' }
New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
$LogFile      = Join-Path $DataDir 'log.txt'
$SettingsFile = Join-Path $DataDir 'settings.json'
function Write-Log([string]$msg) {
    try { Add-Content -Path $LogFile -Value ('{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $msg) } catch {}
}

# ---------------------------------------------------------------- small C# helpers
# Bell(): one soft tone. Root + fifth + octave, plain and steady (no wobble):
# a 90 ms rise, then it fades away evenly in under a second.
# Higher (D) to open or begin, lower (A) to close or go back.
if (-not ('GeomPetSound' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;

public static class GeomPetSound {
    public static byte[] Bell(double root, double seconds, double volume) {
        int rate = 44100;
        int n = (int)(rate * seconds);
        double[] ratio = { 1.0, 1.5, 2.0 };
        double[] amp   = { 1.0, 0.5, 0.18 };
        double attack = 0.09, tailFade = 0.03;
        double norm = 0; foreach (double a in amp) norm += a;
        short[] pcm = new short[n];
        for (int i = 0; i < n; i++) {
            double t = (double)i / rate;
            // rise in a straight line, then fall away smoothly to about a 350th of the peak
            double env = t < attack ? t / attack : Math.Exp(-5.858 * (t - attack) / (seconds - attack));
            double tail = t > seconds - tailFade ? (seconds - t) / tailFade : 1.0;
            double s = 0;
            for (int k = 0; k < ratio.Length; k++) s += amp[k] * Math.Sin(2 * Math.PI * root * ratio[k] * t);
            double v = s / norm * env * tail * volume;
            if (v > 1) v = 1; if (v < -1) v = -1;
            pcm[i] = (short)(v * 32767);
        }
        using (MemoryStream ms = new MemoryStream())
        using (BinaryWriter w = new BinaryWriter(ms)) {
            int dataLen = n * 2;
            w.Write(new byte[] { 82, 73, 70, 70 }); w.Write(36 + dataLen);      // RIFF
            w.Write(new byte[] { 87, 65, 86, 69 });                              // WAVE
            w.Write(new byte[] { 102, 109, 116, 32 }); w.Write(16);              // fmt
            w.Write((short)1); w.Write((short)1); w.Write(rate); w.Write(rate * 2);
            w.Write((short)2); w.Write((short)16);
            w.Write(new byte[] { 100, 97, 116, 97 }); w.Write(dataLen);          // data
            foreach (short x in pcm) w.Write(x);
            w.Flush();
            return ms.ToArray();
        }
    }
}

public static class GeomPetNative {
    [StructLayout(LayoutKind.Sequential)] struct PT { public int X; public int Y; }
    [DllImport("user32.dll")] static extern bool GetCursorPos(out PT p);
    [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr h, int i);
    [DllImport("user32.dll")] static extern int SetWindowLong(IntPtr h, int i, int v);

    public static double[] Cursor() {
        PT p;
        if (GetCursorPos(out p)) return new double[] { p.X, p.Y };
        return null;
    }
    // Keep the pet out of Alt+Tab and the taskbar.
    public static void ToolWindow(IntPtr h) {
        const int GWL_EXSTYLE = -20, WS_EX_TOOLWINDOW = 0x80, WS_EX_APPWINDOW = 0x40000;
        int s = GetWindowLong(h, GWL_EXSTYLE);
        SetWindowLong(h, GWL_EXSTYLE, (s | WS_EX_TOOLWINDOW) & ~WS_EX_APPWINDOW);
    }
}
'@
}

# ---------------------------------------------------------------- settings
$S = @{
    size = 160; solid = 'cube'; sound = $true; anchor = ''; left = $null; top = $null
    tickT = -100.0; fastUntil = -100.0; tickMs = 40; eyeMoved = $false
    yaw = 0.6; pitch = 0.35; spin = 0.0; leanX = 0.0; leanY = 0.0; eyeX = 0.0; eyeY = 0.0
    last = 0.0; breathStart = -100.0; breathEnd = -100.0; rest = $false; closing = $false
    lastCursor = $null; lastMove = 0.0; fallback = $false; renderErr = $false
    bag = $null; lastLine = ''
}
# Size is a slider: from small, up to a solid about half the screen's height.
# (The solid is drawn about 0.6 of its square, so the largest square = height * 0.85.)
Add-Type -AssemblyName PresentationFramework
$SizeMin = 100
$SizeMax = [math]::Max(400, [int][math]::Round([System.Windows.SystemParameters]::PrimaryScreenHeight * 0.85))
# Thirteen solids, picked from equanim's polyhedra library (bt_vfx FractalMesh._base):
# the five Platonic solids, the star of two tetrahedra, and seven gentle relatives.
# Nothing past 60 edges, so the pet stays light. F = faces, for the Euler line.
$SolidTable = [ordered]@{
    'tetrahedron'           = @{ F = 4 }
    'cube'                  = @{ F = 6 }
    'octahedron'            = @{ F = 8 }
    'dodecahedron'          = @{ F = 12 }
    'icosahedron'           = @{ F = 20 }
    'stella octangula'      = @{ F = 8 }
    'cuboctahedron'         = @{ F = 14 }
    'rhombic dodecahedron'  = @{ F = 12 }
    'truncated tetrahedron' = @{ F = 8 }
    'truncated octahedron'  = @{ F = 14 }
    'truncated cube'        = @{ F = 14 }
    'rhombicuboctahedron'   = @{ F = 26 }
    'icosidodecahedron'     = @{ F = 32 }
}
$SolidNames = @($SolidTable.Keys)

if (Test-Path $SettingsFile) {
    try {
        $j = Get-Content -Path $SettingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($key in 'size', 'solid', 'sound', 'anchor', 'left', 'top') {
            if ($null -ne $j.$key) { $S[$key] = $j.$key }
        }
        $S.size = [math]::Max($SizeMin, [math]::Min($SizeMax, [int]$S.size))
        if ($SolidNames -notcontains $S.solid)       { $S.solid = 'cube' }
        $S.size = [int]$S.size; $S.sound = [bool]$S.sound; $S.anchor = [string]$S.anchor
    } catch { Write-Log "settings unreadable, using defaults: $_" }
}

# ---------------------------------------------------------------- geometry
# Every solid comes from its textbook coordinates (a few numbers, shuffled
# and signed), then is scaled so its farthest corner sits on a sphere of
# radius 1. Edges are found by measurement, the same way equanim does it:
# every pair of corners at the shortest distance apart is an edge.
# (The stella octangula uses the second-shortest: the cube's face diagonals.)
$PHI = (1 + [math]::Sqrt(5)) / 2

# Add (a, b, c) in every order (or only the three rotations with -Cyclic), with
# every sign flip (or only those with an even count of minus signs, -EvenMinus).
function Add-Points($list, $seen, [double]$a, [double]$b, [double]$c, [switch]$Cyclic, [switch]$EvenMinus) {
    $orders = if ($Cyclic) { @(@($a, $b, $c), @($b, $c, $a), @($c, $a, $b)) }
              else { @(@($a, $b, $c), @($a, $c, $b), @($b, $a, $c), @($b, $c, $a), @($c, $a, $b), @($c, $b, $a)) }
    foreach ($o in $orders) {
        for ($m = 0; $m -lt 8; $m++) {
            $p = [double[]]@($o[0], $o[1], $o[2]); $minus = 0
            for ($i = 0; $i -lt 3; $i++) {
                if ($m -band (1 -shl $i)) { if ($p[$i] -eq 0) { $minus = -99; break }; $p[$i] = -$p[$i]; $minus++ }
            }
            if ($minus -lt 0) { continue }
            if ($EvenMinus -and ($minus % 2) -ne 0) { continue }
            $key = [string]::Format([Globalization.CultureInfo]::InvariantCulture, '{0:F5}|{1:F5}|{2:F5}', $p[0], $p[1], $p[2])
            if ($seen.Add($key)) { $list.Add($p) }
        }
    }
}

function New-Solid([string]$name) {
    $list = New-Object 'System.Collections.Generic.List[double[]]'
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    $q = 1 / $PHI; $r2 = [math]::Sqrt(2); $edgeRank = 0
    switch ($name) {
        'tetrahedron'           { Add-Points $list $seen 1 1 1 -EvenMinus }
        'cube'                  { Add-Points $list $seen 1 1 1 }
        'octahedron'            { Add-Points $list $seen 1 0 0 }
        'dodecahedron'          { Add-Points $list $seen 1 1 1; Add-Points $list $seen 0 $q $PHI -Cyclic }
        'icosahedron'           { Add-Points $list $seen 0 1 $PHI -Cyclic }
        'stella octangula'      { Add-Points $list $seen 1 1 1; $edgeRank = 1 }
        'cuboctahedron'         { Add-Points $list $seen 1 1 0 }
        'rhombic dodecahedron'  { Add-Points $list $seen 1 1 1; Add-Points $list $seen 2 0 0 }
        'truncated tetrahedron' { Add-Points $list $seen 3 1 1 -EvenMinus }
        'truncated octahedron'  { Add-Points $list $seen 0 1 2 }
        'truncated cube'        { Add-Points $list $seen ($r2 - 1) 1 1 }
        'rhombicuboctahedron'   { Add-Points $list $seen 1 1 (1 + $r2) }
        'icosidodecahedron'     { Add-Points $list $seen 0 0 $PHI; Add-Points $list $seen 0.5 ($PHI / 2) ($PHI * $PHI / 2) -Cyclic }
    }
    $verts = $list.ToArray()
    $n = $verts.Length

    # distances, and the distinct lengths they come in
    $gap = New-Object 'double[]' ($n * $n)
    $lengths = New-Object System.Collections.Generic.List[double]
    for ($i = 0; $i -lt $n; $i++) {
        for ($k = $i + 1; $k -lt $n; $k++) {
            $dx = $verts[$i][0] - $verts[$k][0]; $dy = $verts[$i][1] - $verts[$k][1]; $dz = $verts[$i][2] - $verts[$k][2]
            $len = [math]::Sqrt($dx * $dx + $dy * $dy + $dz * $dz); $gap[$i * $n + $k] = $len
            $fresh = $true
            foreach ($known in $lengths) { if ([math]::Abs($known - $len) -lt 1e-4) { $fresh = $false; break } }
            if ($fresh) { $lengths.Add($len) }
        }
    }
    $lengths.Sort()
    $edgeLen = $lengths[$edgeRank]
    $edgeList = New-Object 'System.Collections.Generic.List[int[]]'
    for ($i = 0; $i -lt $n; $i++) {
        for ($k = $i + 1; $k -lt $n; $k++) {
            if ([math]::Abs($gap[$i * $n + $k] - $edgeLen) -lt 1e-4) { $edgeList.Add([int[]]@($i, $k)) }
        }
    }

    # one scale for every corner, so shapes with two radii keep their true form
    $far = 0.0
    foreach ($p in $verts) { $far = [math]::Max($far, [math]::Sqrt($p[0] * $p[0] + $p[1] * $p[1] + $p[2] * $p[2])) }
    foreach ($p in $verts) { for ($i = 0; $i -lt 3; $i++) { $p[$i] = $p[$i] / $far } }

    return @{ Name = $name; V = $verts; E = $edgeList.ToArray(); F = $SolidTable[$name].F }
}

# ---------------------------------------------------------------- the lines
# The lines live in lines.txt, beside this script: one line of text per row,
# with  |  where the words should break onto a new row. Rows that start with #
# are notes. They are shuffled like a deck, so none repeats until all have been
# seen. Two special rows, {thread} and {euler}, are worked out live from your
# anchor and the shape.
# If lines.txt is missing, these three stand in.
$Deck = @(
    'Just the next small step.'
    '{thread}'
    '{euler}'
)

$LinesFile = Join-Path $PSScriptRoot 'lines.txt'
if (Test-Path -LiteralPath $LinesFile) {
    try {
        $fromFile = @(Get-Content -LiteralPath $LinesFile -Encoding UTF8 |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and -not $_.StartsWith('#') } |
            ForEach-Object { ($_ -split '\s*\|\s*') -join "`n" })
        if ($fromFile.Count -gt 0) { $Deck = $fromFile }
    } catch { Write-Log "lines.txt could not be read: $_" }
}

function Get-NextLine {
    if (-not $S.bag -or $S.bag.Count -eq 0) {
        $S.bag = [System.Collections.ArrayList]@($Deck | Get-Random -Count $Deck.Count)
        if ($S.bag[0] -eq $S.lastLine -and $S.bag.Count -gt 1) { $S.bag.Reverse() }
    }
    $pick = $S.bag[0]; $S.bag.RemoveAt(0); $S.lastLine = $pick
    switch ($pick) {
        '{euler}' {
            $g = $S.geo; $nv = $g.V.Length; $ne = $g.E.Length; $nf = $g.F
            if ($nv - $ne + $nf -eq 2) { "$nv corners, $ne edges, $nf faces.`n$nv, take away $ne, add ${nf}: always 2." }
            else { "$nv corners, $ne edges, $nf faces.`n$nv, take away $ne, add ${nf}: 4.`nTwo tetrahedra, 2 each." }
        }
        '{thread}' {
            if ($S.anchor) { "Lost the thread?`nHover over me." }
            else { "Lost the thread?`nRight-click me, then ⚓." }
        }
        default { $pick }
    }
}

# ---------------------------------------------------------------- -Check (part 1)
if ($Check) {
    Write-Host 'geom-Pet check'
    # corners / edges, from the standard tables
    $expect = @{
        'tetrahedron' = '4/6'; 'cube' = '8/12'; 'octahedron' = '6/12'; 'dodecahedron' = '20/30'; 'icosahedron' = '12/30'
        'stella octangula' = '8/12'; 'cuboctahedron' = '12/24'; 'rhombic dodecahedron' = '14/24'
        'truncated tetrahedron' = '12/18'; 'truncated octahedron' = '24/36'; 'truncated cube' = '24/36'
        'rhombicuboctahedron' = '24/48'; 'icosidodecahedron' = '30/60'
    }
    foreach ($nm in $SolidNames) {
        $g = New-Solid $nm
        $got = '{0}/{1}' -f $g.V.Length, $g.E.Length
        $euler = $g.V.Length - $g.E.Length + $g.F
        Write-Host ('  {0,-22} V/E {1,-6} expected {2,-6} V-E+F={3}  {4}' -f $nm, $got, $expect[$nm], $euler, $(if ($got -eq $expect[$nm]) { 'ok' } else { 'MISMATCH' }))
    }
    $S.geo = New-Solid 'cube'
    $seen = @(); for ($i = 0; $i -lt $Deck.Count; $i++) { $seen += (Get-NextLine) }
    Write-Host ('  deck: {0} lines drawn, {1} distinct' -f $seen.Count, ($seen | Select-Object -Unique).Count)
    $w = [GeomPetSound]::Bell(587.33, 2.8, 0.42)
    Write-Host ('  tone: {0} bytes ({1:N1} s)' -f $w.Length, (($w.Length - 44) / 88200))
}

# ---------------------------------------------------------------- one pet at a time
if (-not $Check) {
    $created = $false
    $Mutex = [System.Threading.Mutex]::new($true, 'Local\geom-Pet', [ref]$created)
    if (-not $created) { return }
}

# ---------------------------------------------------------------- window
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml

$WinXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="geom-Pet" WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False" ResizeMode="NoResize" Opacity="0"
        Width="260" Height="256">
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
    </Grid.RowDefinitions>
    <Grid x:Name="Stage" Grid.Row="0" Width="160" Height="160" HorizontalAlignment="Center" VerticalAlignment="Top">
      <Ellipse x:Name="Hit" Fill="#01FFFFFF"/>
      <Canvas x:Name="Shape" IsHitTestVisible="False">
        <Canvas.Effect>
          <DropShadowEffect Color="#000000" BlurRadius="6" ShadowDepth="0" Opacity="0.55"/>
        </Canvas.Effect>
      </Canvas>
      <Canvas x:Name="Face" IsHitTestVisible="False" Opacity="0">
        <Canvas.Effect>
          <DropShadowEffect Color="#000000" BlurRadius="6" ShadowDepth="0" Opacity="0.55"/>
        </Canvas.Effect>
      </Canvas>
      <Canvas x:Name="Hearts" IsHitTestVisible="False"/>
    </Grid>
    <Grid x:Name="LineHost" Grid.Row="0" Grid.RowSpan="2" VerticalAlignment="Top" Height="160" IsHitTestVisible="False">
      <Border x:Name="LinePlate" Opacity="0" Background="#A6101318" BorderBrush="#2EFFFFFF" BorderThickness="1"
              CornerRadius="2" Padding="11,6,11,7" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,36,0,0">
        <TextBlock x:Name="LineText" FontFamily="Times New Roman, Georgia, serif" FontStyle="Italic" FontSize="14"
                   Foreground="#F2F4F6" TextWrapping="Wrap" TextAlignment="Center" MaxWidth="216"/>
      </Border>
    </Grid>
    <StackPanel Grid.Row="1" HorizontalAlignment="Center" IsHitTestVisible="False" Margin="0,4,0,0">
      <StackPanel.Effect>
        <DropShadowEffect Color="#000000" BlurRadius="8" ShadowDepth="0" Opacity="0.9"/>
      </StackPanel.Effect>
      <TextBlock x:Name="AnchorText" Opacity="0" FontFamily="Segoe UI" FontSize="13" FontStyle="Italic"
                 Foreground="#E6EEF2F6" TextWrapping="Wrap" TextAlignment="Center" MaxWidth="240" Margin="0,0,0,4"/>
    </StackPanel>
  </Grid>
</Window>
'@

$AnchorXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent" Topmost="True"
        ShowInTaskbar="False" SizeToContent="WidthAndHeight" ResizeMode="NoResize">
  <Border Background="#F2181A1E" BorderBrush="#40FFFFFF" BorderThickness="1" CornerRadius="2" Padding="12,10">
    <StackPanel>
      <TextBlock Text="⚓  right now, I'm…" Foreground="#B8E8ECF0" FontFamily="Segoe UI" FontSize="12" Margin="0,0,0,6"/>
      <TextBox x:Name="Field" Width="250" FontFamily="Segoe UI" FontSize="14" Background="#24272C"
               Foreground="#F2F4F6" CaretBrush="#F2F4F6" BorderBrush="#40FFFFFF" Padding="5,3"/>
      <TextBlock Text="↵    ·    esc" Foreground="#70E8ECF0" FontFamily="Segoe UI" FontSize="11"
                 HorizontalAlignment="Right" Margin="0,6,0,0"/>
    </StackPanel>
  </Border>
</Window>
'@

# The per-frame maths runs as compiled code, so the pet stays light: turning
# every corner and moving every line costs well under a millisecond a frame.
if (-not ('GeomPetDraw' -as [type])) {
    $refs = @(
        [System.Windows.Shapes.Line].Assembly.Location,          # PresentationFramework
        [System.Windows.UIElement].Assembly.Location,            # PresentationCore
        [System.Windows.DependencyObject].Assembly.Location,     # WindowsBase
        [System.Xaml.XamlSchemaContext].Assembly.Location        # System.Xaml
    )
    Add-Type -ReferencedAssemblies $refs -TypeDefinition @'
using System;
using System.Windows.Shapes;

public static class GeomPetDraw {
    // turn (yaw), tumble (pitch), then lean toward the cursor (leanY, leanX);
    // project with a soft perspective; far edges fainter.
    public static void Frame(double[][] verts, int[][] edges, Line[] lines,
                             double yaw, double pitch, double leanX, double leanY,
                             double half, double rad, double cam) {
        int n = verts.Length;
        double[] px = new double[n], py = new double[n], pz = new double[n];
        double cyw = Math.Cos(yaw),   syw = Math.Sin(yaw);
        double cpt = Math.Cos(pitch), spt = Math.Sin(pitch);
        double cly = Math.Cos(leanY), sly = Math.Sin(leanY);
        double clx = Math.Cos(leanX), slx = Math.Sin(leanX);
        for (int i = 0; i < n; i++) {
            double x = verts[i][0], y = verts[i][1], z = verts[i][2];
            double x1 = x * cyw + z * syw,   z1 = -x * syw + z * cyw;
            double y1 = y * cpt - z1 * spt,  z2 = y * spt + z1 * cpt;
            double x2 = x1 * cly + z2 * sly, z3 = -x1 * sly + z2 * cly;
            double y2 = y1 * clx - z3 * slx, z4 = y1 * slx + z3 * clx;
            double k = cam / (cam - z4);
            px[i] = half + x2 * rad * k;
            py[i] = half + y2 * rad * k;
            pz[i] = z4;
        }
        for (int j = 0; j < edges.Length && j < lines.Length; j++) {
            int a = edges[j][0], b = edges[j][1];
            Line ln = lines[j];
            ln.X1 = px[a]; ln.Y1 = py[a]; ln.X2 = px[b]; ln.Y2 = py[b];
            ln.Opacity = 0.2 + 0.18 * (pz[a] + pz[b] + 2);
        }
    }
}
'@
}

$win        = [Windows.Markup.XamlReader]::Parse($WinXaml)
$Stage      = $win.FindName('Stage')
$Hit        = $win.FindName('Hit')
$Shape      = $win.FindName('Shape')
$AnchorText = $win.FindName('AnchorText')
$LineText   = $win.FindName('LineText')
$LinePlate  = $win.FindName('LinePlate')
$LineHost   = $win.FindName('LineHost')
$Face       = $win.FindName('Face')
$Hearts     = $win.FindName('Hearts')

$LineBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(236, 239, 243))
$LineBrush.Freeze()
$HeartBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(244, 163, 192))
$HeartBrush.Freeze()
# A heart whose sides bow outward all the way down to the point (no inward curl
# near the tip). Four curves, drawn in a box from -1 to 1 across.
$HeartGeo = [System.Windows.Media.Geometry]::Parse('M 0,-0.35 C 0.25,-0.8 0.95,-0.75 1,-0.2 C 1.03,0.25 0.35,0.8 0,1 C -0.35,0.8 -1.03,0.25 -1,-0.2 C -0.95,-0.75 -0.25,-0.8 0,-0.35 Z')
$HeartGeo.Freeze()
$S.hearts = New-Object System.Collections.ArrayList
$Inv = [Globalization.CultureInfo]::InvariantCulture

$CAM    = 3.6                   # camera distance, in sphere radii
$Canvas = [System.Windows.Controls.Canvas]
$Opac   = [System.Windows.UIElement]::OpacityProperty
$EKF    = [System.Windows.Media.Animation.EasingDoubleKeyFrame]

# ---------------------------------------------------------------- sound
$Tones = @{}
function Initialize-Sound {
    foreach ($nm in 'up', 'down') {
        $root  = if ($nm -eq 'up') { 587.33 } else { 440.0 }   # D to open, A to close
        $bytes = [GeomPetSound]::Bell($root, 0.9, 0.07)
        $secs  = 0.9
        $path  = Join-Path $DataDir "$nm.wav"
        try { [IO.File]::WriteAllBytes($path, $bytes) } catch { Write-Log "wav write: $_" }
        $pool = @()
        for ($i = 0; $i -lt 3; $i++) {
            $mp = New-Object System.Windows.Media.MediaPlayer
            $mp.Add_MediaFailed({ $S.fallback = $true; Write-Log "media player failed; using fallback" })
            $mp.Add_MediaEnded({ param($sender, $e) $sender.Pause(); $sender.Position = [TimeSpan]::Zero })
            $mp.Open([Uri]$path); $mp.Volume = 0.85
            $mp.Pause()                                   # loaded and waiting, not cold
            $pool += $mp
        }
        $Tones[$nm] = @{ bytes = $bytes; pool = $pool; i = 0; secs = $secs }
    }
}
function Play-Tone([string]$nm) {
    if (-not $S.sound -or $Check) { return }
    $T = $Tones[$nm]; if (-not $T) { return }
    try {
        if ($S.fallback) {
            $S.player = New-Object System.Media.SoundPlayer (New-Object IO.MemoryStream (, $T.bytes))
            $S.player.Play(); return
        }
        $mp = $T.pool[$T.i]; $T.i = ($T.i + 1) % $T.pool.Count   # a few players, so tones can overlap like bells
        $mp.Position = [TimeSpan]::Zero; $mp.Play()
    } catch { Write-Log "tone: $_" }
}

# ---------------------------------------------------------------- small helpers
function KT([double]$sec) { [System.Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromSeconds($sec)) }

function Fade($el, [double]$to, [double]$sec, [double]$delay = 0, [scriptblock]$done = $null) {
    $a = New-Object System.Windows.Media.Animation.DoubleAnimation
    $a.To = $to
    $a.Duration = New-Object System.Windows.Duration ([TimeSpan]::FromSeconds($sec))
    $a.BeginTime = [TimeSpan]::FromSeconds($delay)
    $a.EasingFunction = New-Object System.Windows.Media.Animation.SineEase
    if ($done) { $a.Add_Completed($done) }
    $el.BeginAnimation($Opac, $a)
}

# Fade something in gently, hold it, then let it fade away again.
function Show-Soft($el, [double]$hold) {
    $a = New-Object System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames
    [void]$a.KeyFrames.Add($EKF::new(1.0, (KT 0.7)))
    [void]$a.KeyFrames.Add($EKF::new(1.0, (KT (0.7 + $hold))))
    [void]$a.KeyFrames.Add($EKF::new(0.0, (KT (2.3 + $hold))))
    $el.BeginAnimation($Opac, $a)
}

function Show-Text($tb, [string]$text, [double]$hold) {
    $tb.Text = $text
    $a = New-Object System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames
    [void]$a.KeyFrames.Add($EKF::new(1.0, (KT 0.7)))
    [void]$a.KeyFrames.Add($EKF::new(1.0, (KT (0.7 + $hold))))
    [void]$a.KeyFrames.Add($EKF::new(0.0, (KT (2.3 + $hold))))
    $tb.BeginAnimation($Opac, $a)
}

function Save-Settings {
    try {
        @{ size = $S.size; solid = $S.solid; sound = $S.sound; anchor = $S.anchor; left = $win.Left; top = $win.Top } |
            ConvertTo-Json | Set-Content -Path $SettingsFile -Encoding UTF8
    } catch { Write-Log "save: $_" }
}

function Build-Lines {
    $Shape.Children.Clear()
    $count = $S.geo.E.Length
    $lines = New-Object 'System.Windows.Shapes.Line[]' $count
    for ($k = 0; $k -lt $count; $k++) {
        $ln = New-Object System.Windows.Shapes.Line
        $ln.Stroke = $LineBrush; $ln.StrokeThickness = 1.1
        $ln.StrokeStartLineCap = 'Round'; $ln.StrokeEndLineCap = 'Round'
        [void]$Shape.Children.Add($ln); $lines[$k] = $ln
    }
    $S.lines = $lines
}

# The face is only seen for a while after a click, like a tickle.
# Two dot eyes appear, give one happy blink, and fade again.
#
# The blink is five key drawings. Each row is: seconds, how open (1 = a round dot,
# 0 = the closed happy arch  n ), and a small size change.
#   open -> widen (a little anticipation) -> closed -> hold the smile -> open
# It is a long blink: a happiness so large and sudden that the eyes stay shut in
# their squint for most of the tickle. They open again only briefly, just before
# the face fades away. So the two last keys depend on how long the words stay up.
$BlinkStart  = 0.5                      # the eyes fade in open first, then squint
$BlinkClosed = 4 / 12
$BlinkKeys   = @()
$BlinkDur    = 0.0
function Set-BlinkKeys([double]$hold) {
    $fadeOut = 0.7 + $hold - $BlinkStart        # when the face starts to fade, counted from the blink's start
    $script:BlinkKeys = @(
        @(0.0,              1.0, 1.00),
        @((1 / 12),         1.0, 1.12),
        @($BlinkClosed,     0.0, 1.05),
        @(($fadeOut - 0.95), 0.0, 1.00),
        @(($fadeOut - 0.50), 1.0, 1.00)
    )
    $script:BlinkDur = $fadeOut - 0.50
}

# The inbetweens: for any moment, the drawing between two keys. The spacing is
# eased, so the eye moves slowly out of one key and slowly into the next.
function Get-BlinkPose([double]$bt) {
    if ($bt -le 0) { return @(1.0, 1.0) }
    if ($bt -ge $BlinkDur) { return @(1.0, 1.0) }
    $i = 0
    while ($i -lt ($BlinkKeys.Length - 2) -and $bt -ge $BlinkKeys[$i + 1][0]) { $i++ }
    $a = $BlinkKeys[$i]; $b = $BlinkKeys[$i + 1]
    $u = ($bt - $a[0]) / ($b[0] - $a[0])
    $u = $u * $u * (3 - 2 * $u)
    $open = $a[1] + ($b[1] - $a[1]) * $u
    $scale = $a[2] + ($b[2] - $a[2]) * $u
    return @($open, $scale)
}

# Draw both eyes at one openness. The top lid is always the same half circle.
# The lower lid is half an ellipse that swings from below (a full dot), through
# flat, up to meet the top lid (the arch).
function Set-EyeShape([double]$open, [double]$scale) {
    $r = $S.eyeR * $scale
    $k = 2 * [math]::Max(0.0, [math]::Min(1.0, $open)) - 1
    $ry = [math]::Max(0.01, [math]::Abs($k) * $r)
    $sweep = 0; if ($k -ge 0) { $sweep = 1 }
    $text = [string]::Format($Inv, 'M {0},0 A {1},{1} 0 0 1 {1},0 A {1},{2} 0 0 {3} {0},0 Z', (-$r), $r, $ry, $sweep)
    $geo = [System.Windows.Media.Geometry]::Parse($text)
    $geo.Freeze()
    foreach ($eye in $S.eyes) { $eye.Data = $geo }
}

function Update-Face {
    $Face.Children.Clear()
    $eyes = New-Object 'System.Windows.Shapes.Path[]' 2
    for ($i = 0; $i -lt 2; $i++) {
        $eye = New-Object System.Windows.Shapes.Path
        $eye.Stroke = $LineBrush; $eye.Fill = $LineBrush
        $eye.StrokeThickness = [math]::Max(1.4, $S.size * 0.006)
        $eye.StrokeLineJoin = 'Round'
        [void]$Face.Children.Add($eye); $eyes[$i] = $eye
    }
    $S.eyes = $eyes; $S.eyeR = [math]::Max(3.0, $S.size * 0.032)
    Set-EyeShape 1 1
}

# Two or three small hearts open out from the middle of the shape, slow down,
# and fade: a soft burst that stays inside the shape's own outline.
function Add-Hearts([double]$delay = 0) {
    $count = Get-Random -Minimum 2 -Maximum 4
    for ($i = 0; $i -lt $count; $i++) {
        $w = [math]::Max(9.0, $S.size * (0.05 + 0.03 * (Get-Random -Maximum 100) / 100))
        # directions fan across the upper half: up-left, up, up-right (never down over the words)
        $deg = -150 + ($i + 0.5) * (120 / $count) + ((Get-Random -Maximum 200) - 100) / 10
        $reach = $S.size * (0.12 + 0.05 * (Get-Random -Maximum 100) / 100)
        $el = New-Object System.Windows.Shapes.Path
        $el.Data = $HeartGeo; $el.Stretch = 'Uniform'; $el.Width = $w; $el.Height = $w
        $el.Stroke = $HeartBrush; $el.StrokeThickness = 1.3; $el.StrokeLineJoin = 'Round'; $el.Opacity = 0
        [void]$Hearts.Children.Add($el)
        [void]$S.hearts.Add(@{
            el = $el; w = $w; age = -($delay + 0.3 * $i); life = 3.2
            x = $S.size / 2; y = $S.size * 0.46
            dx = [math]::Cos($deg * [math]::PI / 180) * $reach
            dy = [math]::Sin($deg * [math]::PI / 180) * $reach
        })
    }
}

function Update-Hearts([double]$dt) {
    for ($i = $S.hearts.Count - 1; $i -ge 0; $i--) {
        $h = $S.hearts[$i]
        $h.age += $dt
        if ($h.age -lt 0) { continue }
        $q = $h.age / $h.life
        if ($q -ge 1) { $Hearts.Children.Remove($h.el); $S.hearts.RemoveAt($i); continue }
        $go = 1 - [math]::Pow(1 - $q, 3)             # quick at first, then easing to rest
        $x = $h.x + $h.dx * $go; $y = $h.y + $h.dy * $go
        # gentle entry, gentle exit: a slow smooth rise in, a long smooth fade out
        $in = [math]::Min(1, $q / 0.25); $out = [math]::Min(1, (1 - $q) / 0.45)
        $h.el.Opacity = 0.9 * ($in * $in * (3 - 2 * $in)) * ($out * $out * (3 - 2 * $out))
        $Canvas::SetLeft($h.el, $x - $h.w / 2)
        $Canvas::SetTop($h.el, $y - $h.w / 2)
    }
}

function Set-Solid([string]$name, [switch]$Soft) {
    $S.solid = $name
    if ($Soft) {
        Fade $Shape 0 0.9 0 { $S.geo = New-Solid $S.solid; Build-Lines; Fade $Shape 1 1.4 }
    } else {
        $S.geo = New-Solid $name; Build-Lines
    }
}

function Set-Size([int]$px) {
    $oldW = $win.Width; $oldSize = $Stage.Height
    $S.size = $px
    $Stage.Width = $px; $Stage.Height = $px
    $win.Width  = [math]::Max(260, $px + 40)
    $win.Height = $px + 96
    $win.Left  += ($oldW - $win.Width) / 2
    $win.Top   += ($oldSize - $px) / 2
    $AnchorText.MaxWidth = $win.Width - 20; $LineText.MaxWidth = $win.Width - 44
    # the line of text sits in the middle of the shape, just under the eyes
    # only the shape itself answers a click, not the empty space around it
    $Hit.Width = $px * 0.64; $Hit.Height = $px * 0.64
    $LineHost.Height = $px
    $LinePlate.Margin = New-Object System.Windows.Thickness 0, ($px * 0.22), 0, 0
    $LineText.FontSize = [math]::Max(13.5, [math]::Min(20.5, $px * 0.042))
    Update-Face
}

function Set-Rest([bool]$on) {
    $S.rest = $on
    if ($on) { Fade $win 0.2 1.6; $timer.Interval = [TimeSpan]::FromMilliseconds(100) }
    else     { Fade $win 0.92 1.0; $timer.Interval = [TimeSpan]::FromMilliseconds(40); $S.tickMs = 40 }
}

function Start-Breathe {
    # Six slow breaths: five seconds growing, five seconds settling. No counter.
    $t = $script:clock.Elapsed.TotalSeconds
    $S.breathStart = $t; $S.breathEnd = $t + 60
}

function Close-Pet {
    if ($S.closing) { return }
    $S.closing = $true
    Save-Settings
    Play-Tone 'down'
    Fade $win 0 1.6
    # stay (unseen) until the closing tone has finished ringing, then leave
    $wait = 1.7
    if ($S.sound -and $Tones['down']) { $wait = [math]::Max(1.7, $Tones['down'].secs + 0.2) }
    $bye = New-Object System.Windows.Threading.DispatcherTimer
    $bye.Interval = [TimeSpan]::FromSeconds($wait)
    $bye.Add_Tick({ param($sender, $e) $sender.Stop(); $win.Close() })
    $bye.Start()
}

# ---------------------------------------------------------------- gaze
# The whole solid leans a little toward your cursor. When the cursor has been still for four minutes and
# then moves again, the shape gives a small spin: you're back.
function Update-Gaze([double]$t, [double]$dt) {
    $c = [GeomPetNative]::Cursor()
    if ($null -eq $c -or $null -eq $S.fromDevice) { return }
    if ($S.lastCursor) {
        if (([math]::Abs($c[0] - $S.lastCursor[0]) + [math]::Abs($c[1] - $S.lastCursor[1])) -gt 2) {
            if ($t - $S.lastMove -gt 240) { $S.spin += 0.9 }
            $S.lastMove = $t
        }
    } else { $S.lastMove = $t }
    $S.lastCursor = $c

    $p  = $S.fromDevice.Transform((New-Object System.Windows.Point($c[0], $c[1])))
    $dx = $p.X - ($win.Left + $win.Width / 2)
    $dy = $p.Y - ($win.Top + $S.size / 2)
    $dist = [math]::Sqrt($dx * $dx + $dy * $dy)
    $ex = 0.0; $ey = 0.0
    if ($dist -gt 1) { $m = [math]::Min($dist / 350, 1); $ex = $dx / $dist * $m; $ey = $dy / $dist * $m }
    $ty = [math]::Max(-1, [math]::Min(1, $dx / 700)) * 0.30
    $tx = -[math]::Max(-1, [math]::Min(1, $dy / 700)) * 0.30

    $easeLean = 1 - [math]::Exp(-$dt / 0.9)   # slow head-turn
    $easeEye  = 1 - [math]::Exp(-$dt / 0.6)   # eyes a little quicker
    $S.leanY += ($ty - $S.leanY) * $easeLean; $S.leanX += ($tx - $S.leanX) * $easeLean
    $S.eyeX  += ($ex - $S.eyeX) * $easeEye;   $S.eyeY  += ($ey - $S.eyeY) * $easeEye
}

# ---------------------------------------------------------------- one frame
# Two slow turns at speeds in the golden ratio, so the tumble never quite repeats.
function Render {
    try {
        $t  = $script:clock.Elapsed.TotalSeconds
        $dt = $t - $S.last; $S.last = $t
        if ($dt -le 0) { return }
        if ($dt -gt 0.1) { $dt = 0.1 }
        Update-Gaze $t $dt

        $base = 0.17
        if ($S.rest) { $base = 0.05 } elseif ($t -lt $S.breathEnd) { $base = 0.09 }
        $S.spin *= [math]::Exp(-$dt / 1.4)
        $w = $base + $S.spin
        $S.yaw   += $w * $dt
        $S.pitch += $w * $dt / $PHI

        $breath = 1.0
        if ($t -lt $S.breathEnd) {
            $u = $t - $S.breathStart
            $breath = 1 + 0.16 * (0.5 - 0.5 * [math]::Cos(2 * [math]::PI * $u / 10))
        }

        $half = $S.size / 2
        $rad  = $S.size * 0.28 * $breath
        [GeomPetDraw]::Frame($S.geo.V, $S.geo.E, $S.lines, $S.yaw, $S.pitch, $S.leanX, $S.leanY, $half, $rad, $CAM)
        # the eyes sit a little above the middle and drift a touch toward the cursor
        $ey = $half - $S.size * 0.05 + $S.eyeY * $S.size * 0.012
        $ex = $S.eyeX * $S.size * 0.02
        $Canvas::SetLeft($S.eyes[0], $half - $S.size * 0.085 + $ex); $Canvas::SetTop($S.eyes[0], $ey)
        $Canvas::SetLeft($S.eyes[1], $half + $S.size * 0.085 + $ex); $Canvas::SetTop($S.eyes[1], $ey)
        # the blink: a fresh drawing of the eyes on every frame while it lasts
        $bt = $t - $S.tickT - $BlinkStart
        if ($bt -ge 0 -and $bt -le $BlinkDur) {
            $ps = Get-BlinkPose $bt
            Set-EyeShape $ps[0] $ps[1]; $S.eyeMoved = $true
        } elseif ($S.eyeMoved) { Set-EyeShape 1 1; $S.eyeMoved = $false }
        # run at about 60 frames a second while the tickle plays, then settle back to 25
        if (-not $S.rest) {
            $want = 40; if ($t -lt $S.fastUntil) { $want = 16 }
            if ($S.tickMs -ne $want) { $S.tickMs = $want; $timer.Interval = [TimeSpan]::FromMilliseconds($want) }
        }
        Update-Hearts $dt
    } catch {
        if (-not $S.renderErr) { Write-Log "render: $_"; $S.renderErr = $true }
    }
}

# ---------------------------------------------------------------- anchor
function Show-Anchor([double]$hold) {
    if ($S.anchor) { Show-Text $AnchorText ('→ ' + $S.anchor) $hold }
}

function Show-AnchorBox {
    $box   = [Windows.Markup.XamlReader]::Parse($AnchorXaml)
    $field = $box.FindName('Field')
    $field.Text = $S.anchor
    $box.Tag  = 'cancel'
    $box.Left = $win.Left + 2
    $wa = [System.Windows.SystemParameters]::WorkArea
    $box.Top = if ($win.Top + $S.size + 130 -gt $wa.Bottom) { $win.Top - 110 } else { $win.Top + $S.size + 8 }
    $field.Add_KeyDown({
        param($sender, $e)
        $owner = [System.Windows.Window]::GetWindow($sender)
        if ($e.Key -eq 'Return')     { $owner.Tag = 'save'; $owner.Close() }
        elseif ($e.Key -eq 'Escape') { $owner.Close() }
    })
    $box.Add_ContentRendered({
        param($sender, $e)
        $sender.Activate() | Out-Null
        $f = $sender.FindName('Field'); [void]$f.Focus(); $f.SelectAll()
    })
    [void]$box.ShowDialog()
    if ($box.Tag -eq 'save') {
        $S.anchor = $field.Text.Trim()
        Save-Settings
        Play-Tone 'up'
        Show-Anchor 4
    } else {
        Play-Tone 'down'
    }
}

# ---------------------------------------------------------------- menu
$Menu = New-Object System.Windows.Controls.ContextMenu
function Add-MenuItem($parent, [string]$header, [scriptblock]$onClick, $tag = $null) {
    $mi = New-Object System.Windows.Controls.MenuItem
    $mi.Header = $header; $mi.Tag = $tag
    if ($onClick) { $mi.Add_Click($onClick) }
    [void]$parent.Items.Add($mi)
    return $mi
}

[void](Add-MenuItem $Menu '⚓   anchor…' { Show-AnchorBox })
[void](Add-MenuItem $Menu '◯   breathe' { Play-Tone 'up'; if ($S.rest) { Set-Rest $false }; Start-Breathe })

$ShapeMenu = Add-MenuItem $Menu '△   shape' $null
foreach ($nm in $SolidNames) {
    [void](Add-MenuItem $ShapeMenu $nm { param($sender, $e) Play-Tone 'up'; Set-Solid $sender.Tag -Soft; Save-Settings } $nm)
}
$SizeItem = New-Object System.Windows.Controls.MenuItem
$SizeItem.StaysOpenOnClick = $true
$SizePanel = New-Object System.Windows.Controls.StackPanel
$SizePanel.Orientation = 'Horizontal'
$SizeLabel = New-Object System.Windows.Controls.TextBlock
$SizeLabel.Text = '◫   size'; $SizeLabel.VerticalAlignment = 'Center'
$SizeSlider = New-Object System.Windows.Controls.Slider
$SizeSlider.Minimum = $SizeMin; $SizeSlider.Maximum = $SizeMax
$SizeSlider.Width = 170; $SizeSlider.Margin = New-Object System.Windows.Thickness 14, 0, 0, 0; $SizeSlider.VerticalAlignment = 'Center'
$SizeSlider.IsMoveToPointEnabled = $true
[void]$SizePanel.Children.Add($SizeLabel); [void]$SizePanel.Children.Add($SizeSlider)
$SizeItem.Header = $SizePanel
[void]$Menu.Items.Add($SizeItem)
$SizeSlider.Add_ValueChanged({
    if ($S.syncing) { return }
    Set-Size ([int][math]::Round($SizeSlider.Value))
})
$SoundItem = Add-MenuItem $Menu '♪   sound' {
    $S.sound = -not $S.sound
    if ($S.sound) { Play-Tone 'up' }
    Save-Settings
}
$RestItem = Add-MenuItem $Menu '◐   rest' {
    if ($S.rest) { Play-Tone 'up'; Set-Rest $false } else { Play-Tone 'down'; Set-Rest $true }
}
[void]$Menu.Items.Add((New-Object System.Windows.Controls.Separator))
[void](Add-MenuItem $Menu '✕   close' { Close-Pet })

$Menu.Add_Opened({
    Play-Tone 'up'
    foreach ($mi in $ShapeMenu.Items) { $mi.IsChecked = ($mi.Tag -eq $S.solid) }
    $S.syncing = $true; $SizeSlider.Value = $S.size; $S.syncing = $false
    $SoundItem.IsChecked = $S.sound
    $RestItem.IsChecked  = $S.rest
})
$Menu.Add_Closed({ if (-not $S.closing) { Save-Settings } })
$Hit.ContextMenu = $Menu

# ---------------------------------------------------------------- mouse
# The pet is carried by hand rather than with DragMove: Windows' own move stops a window at the
# top edge of the screen, and the pet should be free to peek over any edge, top included.
function Get-CursorDip {
    $c = [GeomPetNative]::Cursor()
    if ($null -eq $c) { return $null }
    $p = New-Object System.Windows.Point($c[0], $c[1])
    if ($null -ne $S.fromDevice) { $p = $S.fromDevice.Transform($p) }
    return $p
}
$Hit.Add_MouseLeftButtonDown({
    param($sender, $e)
    Play-Tone 'up'                                   # the press itself answers, at once
    $S.drag = @{ p0 = (Get-CursorDip); x0 = $win.Left; y0 = $win.Top; moved = $false }
    [void]$Hit.CaptureMouse()
    $e.Handled = $true
})
$Hit.Add_MouseMove({
    param($sender, $e)
    $d = $S.drag
    if ($null -eq $d -or $null -eq $d.p0) { return }
    $p = Get-CursorDip
    if ($null -eq $p) { return }
    $dx = $p.X - $d.p0.X; $dy = $p.Y - $d.p0.Y
    if (-not $d.moved -and ([math]::Abs($dx) + [math]::Abs($dy)) -le 3) { return }
    $d.moved = $true
    $win.Left = $d.x0 + $dx; $win.Top = $d.y0 + $dy
})
$Hit.Add_LostMouseCapture({                          # e.g. a window popped up mid-drag
    $d = $S.drag; $S.drag = $null
    if ($null -ne $d -and $d.moved) { Save-Settings }
})
$Hit.Add_MouseLeftButtonUp({
    param($sender, $e)
    $d = $S.drag; $S.drag = $null
    if ($Hit.IsMouseCaptured) { $Hit.ReleaseMouseCapture() }
    if ($null -eq $d) { return }
    if ($d.moved) { Save-Settings; return }
    if ($S.rest) { Set-Rest $false; return }
    $S.spin += 1.8                                   # a little flick, like a nudged globe
    $text = Get-NextLine
    $hold = 4.5 + 0.06 * $text.Length
    $now = $script:clock.Elapsed.TotalSeconds
    Set-BlinkKeys $hold                              # squint for as long as the words stay up
    Set-EyeShape 1 1                                 # open dot eyes to begin with
    $S.tickT = $now; $S.fastUntil = $now + $hold + 2.6
    Add-Hearts ($BlinkStart + $BlinkClosed)          # the hearts open out as the eyes close
    $LineText.Text = $text
    # words lean in italics; a lone heart stands upright
    $LineText.FontStyle = [System.Windows.FontStyles]::Italic
    if ($text.Trim() -eq [string][char]0x2764) { $LineText.FontStyle = [System.Windows.FontStyles]::Normal }
    Show-Soft $LinePlate $hold                       # words on a soft dark plate, readable over anything
    Show-Soft $Face $hold                            # the eyes come and go with the words
})
$Hit.Add_MouseEnter({ if ($S.anchor) { $AnchorText.Text = '→ ' + $S.anchor; Fade $AnchorText 1 0.5 } })
$Hit.Add_MouseLeave({ Fade $AnchorText 0 1.2 1.5 })

# ---------------------------------------------------------------- start
$win.Dispatcher.Add_UnhandledException({ param($sender, $e) Write-Log "unhandled: $($e.Exception.Message)"; $e.Handled = $true })

$win.Add_SourceInitialized({
    try {
        $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($win)).Handle
        [GeomPetNative]::ToolWindow($hwnd)
        $S.fromDevice = [System.Windows.PresentationSource]::FromVisual($win).CompositionTarget.TransformFromDevice
    } catch { Write-Log "init: $_" }
})

Set-Size $S.size
$S.geo = New-Solid $S.solid
Build-Lines

# place it where it was, or bottom-right if that spot is gone (e.g. a monitor unplugged)
$vl = [System.Windows.SystemParameters]::VirtualScreenLeft
$vt = [System.Windows.SystemParameters]::VirtualScreenTop
$vw = [System.Windows.SystemParameters]::VirtualScreenWidth
$vh = [System.Windows.SystemParameters]::VirtualScreenHeight
$onScreen = ($null -ne $S.left -and $null -ne $S.top -and
             $S.left -ge $vl - 40 -and $S.left -le $vl + $vw - 80 -and
             $S.top  -ge $vt - $S.size + 40 -and $S.top  -le $vt + $vh - 80)   # may peek over the top
if ($onScreen) { $win.Left = [double]$S.left; $win.Top = [double]$S.top }
else {
    $wa = [System.Windows.SystemParameters]::WorkArea
    $win.Left = $wa.Right - $win.Width - 24
    $win.Top  = $wa.Bottom - $win.Height - 16
}

$script:clock = [Diagnostics.Stopwatch]::StartNew()
$timer = New-Object System.Windows.Threading.DispatcherTimer ([System.Windows.Threading.DispatcherPriority]::Render)
$timer.Interval = [TimeSpan]::FromMilliseconds(40)   # 25 frames a second: smooth enough, light on the laptop
$timer.Add_Tick({ Render })

if ($Check) {
    Render
    Write-Host ('  window: built, {0} edges drawn, size {1}' -f $S.lines.Count, $S.size)
    Write-Host '  all good'
    return
}

Initialize-Sound
$win.Add_ContentRendered({
    $timer.Start()
    Fade $win 0.92 1.6
    $hello = New-Object System.Windows.Threading.DispatcherTimer
    $hello.Interval = [TimeSpan]::FromMilliseconds(450)       # give the player a moment to open
    $hello.Add_Tick({ param($sender, $e) $sender.Stop(); Play-Tone 'up'; Show-Anchor 3 })
    $hello.Start()
})
$win.Add_Closed({ $timer.Stop() })

[void]$win.ShowDialog()
try { $Mutex.ReleaseMutex() } catch {}
