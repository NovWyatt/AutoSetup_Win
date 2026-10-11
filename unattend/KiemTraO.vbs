' AutoSetup_Win: kiem tra o dia truoc khi Windows Setup tu dong XOA SACH o (chay trong WinPE).
' Cach goi: cscript //nologo //E:vbscript KiemTraO.vbs <so o> <dung luong toi thieu GB>
' Chi cho xoa khi: may khoi dong UEFI, may co DUNG MOT o trong (khong tinh USB, the nho), o do dung la
' o duoc chon va du dung luong. Sai bat ky dieu kien nao: bao loi, tra ma 1 (lenh goi se khoi dong lai may).
' Hop thong bao: 4112 = vbCritical + vbSystemModal (nam tren cua so Windows Setup).
' Bai thu: dat AUTOSETUP_TEST_DISKS="so/giao tiep/loai/GB;..." va AUTOSETUP_TEST_FIRMWARE (2 = UEFI).
' File nay duoc TaoUnattend.ps1 ghi ra X:\ bang lenh echo cua cmd: KHONG dung ky tu va, gach dung, nho hon,
' lon hon, mu, phan tram; dong trong va dong chu thich bi bo khi nhung vao file unattend.
Option Explicit
Dim args, target, minGB, sh, testDisks, firmware, count, found, sizeGB, msg, wmi, d, it, f
Set args = WScript.Arguments
Set sh = CreateObject("WScript.Shell")
testDisks = sh.Environment("PROCESS").Item("AUTOSETUP_TEST_DISKS")
target = ""
minGB = "0"
If args.Count = 2 Then
    target = args(0)
    minGB = args(1)
End If
count = 0
found = False
sizeGB = 0
msg = ""

Function NzStr(v)
    If IsNull(v) Or IsEmpty(v) Then
        NzStr = ""
    Else
        NzStr = CStr(v)
    End If
End Function

Sub Consider(index, iface, media, sizeBytes)
    If UCase(NzStr(iface)) = "USB" Then Exit Sub
    If InStr(1, NzStr(media), "Removable", 1) Then Exit Sub
    count = count + 1
    If NzStr(index) = NzStr(target) Then
        found = True
        If IsNumeric(NzStr(sizeBytes)) Then sizeGB = CDbl(sizeBytes) / 1073741824
    End If
End Sub

If Not IsNumeric(target) Then msg = "Khong biet o nao se bi xoa (so o: " + NzStr(target) + "). Hay khoi dong bang USB Ventoy, hoac dung file unattend tao voi -DiskId."

If msg = "" Then
    If testDisks = "" Then
        firmware = ""
        On Error Resume Next
        firmware = sh.RegRead("HKLM\System\CurrentControlSet\Control\PEFirmwareType")
        On Error GoTo 0
    Else
        firmware = sh.Environment("PROCESS").Item("AUTOSETUP_TEST_FIRMWARE")
    End If
    If Not (NzStr(firmware) = "2") Then msg = "May dang khoi dong kieu Legacy BIOS (khong phai UEFI). Ban tu dong xoa o chi tao phan vung cho UEFI."
End If

If msg = "" Then
    If testDisks = "" Then
        On Error Resume Next
        Set wmi = GetObject("winmgmts:\\.\root\cimv2")
        If Err.Number Then msg = "Khong doc duoc danh sach o dia (WMI): " + Err.Description
        On Error GoTo 0
        If msg = "" Then
            For Each d In wmi.InstancesOf("Win32_DiskDrive")
                Consider d.Index, d.InterfaceType, d.MediaType, d.Size
            Next
        End If
    Else
        For Each it In Split(testDisks, ";")
            f = Split(it, "/")
            Consider f(0), f(1), f(2), CDbl(f(3)) * 1073741824
        Next
    End If
End If

If msg = "" Then
    If count = 0 Then msg = "Khong thay o cung nao trong may."
End If
If msg = "" Then
    If Not (count = 1) Then msg = "May co " + CStr(count) + " o cung trong. Tu dong xoa chi chay khi may co dung 1 o, de khong xoa nham o du lieu."
End If
If msg = "" Then
    If Not found Then msg = "O so " + NzStr(target) + " khong phai o cung trong may."
End If
If msg = "" Then
    If Sgn(sizeGB - CDbl(minGB)) = -1 Then msg = "O chi co " + CStr(Round(sizeGB)) + " GB, can it nhat " + NzStr(minGB) + " GB."
End If

If msg = "" Then
    WScript.Echo "OK: se xoa o so " + NzStr(target) + " (" + CStr(Round(sizeGB)) + " GB)."
    WScript.Quit 0
End If
WScript.Echo "DUNG: " + msg
If Not (testDisks = "") Then WScript.Quit 1
msg = msg + vbCrLf + vbCrLf + "Windows Setup dung lai de khong mat du lieu, may se khoi dong lai."
msg = msg + vbCrLf + "Hay chon muc Chon-o-bang-tay trong menu Ventoy."
MsgBox msg, 4112, "AutoSetup - DUNG tu dong xoa o"
WScript.Quit 1
