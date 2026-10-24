Attribute VB_Name = "UzTranslitRibbon"
' =====================================================================================
'  UzTranslit ribbon tab (Office 2007 and later) -- every button of office-vba/ribbon/customUI*.xml calls
'  UzRibbon_OnAction. Needs the UzTranslit module in the same file. tools/add_ribbon.py puts the ribbon into a
'  macro-enabled file (.dotm / .docm, .xlam / .xlsm, .ppam / .pptm); see docs/OFFICE_INSTALL.md.
' =====================================================================================
Option Explicit

' control is an IRibbonControl; As Object needs no reference to the Office object library
Public Sub UzRibbon_OnAction(control As Object)
    Select Case control.Id
        Case "uzAutoToNew": UzTranslit_AutoToNew
        Case "uzAutoToLat": UzTranslit_AutoToLat
        Case "uzAutoToCyr": UzTranslit_AutoToCyr
        Case "uzLatToNew": UzTranslit_LatToNew
        Case "uzNewToLat": UzTranslit_NewToLat
        Case "uzCyrToNew": UzTranslit_CyrToNew
        Case "uzCyrToLat": UzTranslit_CyrToLat
        Case "uzNewToCyr": UzTranslit_NewToCyr
        Case "uzLatToCyr": UzTranslit_LatToCyr
        Case "uzSelfTest": UzSelfTest
    End Select
End Sub
