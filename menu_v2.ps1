# 1. Forzar codificación de salida para la consola
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# 1b. Ampliar buffer y ventana de consola para ver el menú completo
try {
    $w = $Host.UI.RawUI.WindowSize
    $b = $Host.UI.RawUI.BufferSize
    if ($b.Width -lt 120)  { $b.Width  = 120 }
    if ($b.Height -lt 3000) { $b.Height = 3000 }
    $Host.UI.RawUI.BufferSize = $b
    if ($w.Width -lt 120)  { $w.Width  = 120 }
    if ($w.Height -lt 50)  { $w.Height = 50 }
    $Host.UI.RawUI.WindowSize = $w
} catch {}

# 2. Configuración de ubicación y variables globales
if ($PSScriptRoot) { Set-Location -LiteralPath $PSScriptRoot }
if (-not $script:ExecutedOptions) { $script:ExecutedOptions = @{} }
$global:messages = @()

# ---------------------------------------

# Definición de comandos con estado inicial

$commands = @(

# ---------------------------------------
# ---------------------------------------
# OK - claude
@{
    Name     = "000 - Reiniciar el sistema operativo"
    Action   = {
        try {
            Clear-Messages
            Update-Messages "-----------------------------------------"
            Update-Messages "⚠️  Vas a reiniciar el sistema operativo."
            Update-Messages "-----------------------------------------"
            $confirm = Read-Host "¿Estás seguro? (S/N)"

            if ($confirm -eq "S" -or $confirm -eq "s") {
                Update-Messages "Reiniciando el sistema operativo en breve..."
                Start-Sleep -Seconds 2
                Restart-Computer -Force -Confirm:$false
            } else {
                Update-Messages "Reinicio cancelado. Volviendo al menú..."
                Start-Sleep -Seconds 1
                Clear-Messages
            }
        }
        catch {
            Update-Messages "❌ Error al reiniciar: $($_.Exception.Message)"
        }
    }
    Executed = $false
}

# ---------------------------------------
# ---------------------------------------
# OK - claude
@{
    Name   = "001 - Configurar política de ejecución"
    Action = {
        try {
            Clear-Messages
            Update-Messages "Configurando política de ejecución..."
            Set-ExecutionPolicy -Scope LocalMachine -ExecutionPolicy RemoteSigned -Force
            Update-Messages "✅ Política de ejecución configurada correctamente."
        }
        catch [System.Security.AccessControl.PrivilegeNotHeldException] {
            Update-Messages "❌ No se tienen privilegios necesarios para modificar políticas."
        }
        catch [System.UnauthorizedAccessException] {
            Update-Messages "❌ Acceso denegado. Asegúrate de ejecutar como administrador."
        }
        catch {
            Update-Messages "❌ Error al configurar política de ejecución: $($_.Exception.Message)"
        }
    }
    Executed = $false
}

# ---------------------------------------
# ---------------------------------------
# OK - claude
@{
    Name     = "002 - Crear punto de restauración (forzado y verificado)"
    Action   = {

        # --- 1) Verificar administrador ---
        $currentPrincipal = New-Object Security.Principal.WindowsPrincipal(
            [Security.Principal.WindowsIdentity]::GetCurrent()
        )
        if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Update-Messages "❌ Error: Este script requiere ejecutarse como administrador."
            return
        }

        Clear-Messages
        Update-Messages "Iniciando tarea: Crear punto de restauración..."

        # --- 2) Verificar espacio libre mínimo en C: (mínimo 300 MB) ---
        $freeGB = (Get-PSDrive -Name C -ErrorAction SilentlyContinue).Free / 1GB
        if ($freeGB -lt 0.3) {
            Update-Messages "❌ Espacio insuficiente en C: ($([math]::Round($freeGB,2)) GB). Se necesitan al menos 300 MB."
            return
        }

        # --- 3) Forzar protección del sistema al 5% via VSSAdmin (sin intervención humana) ---
        try {
            Update-Messages "Configurando protección del sistema al 5% en C:..."

            Set-ItemProperty `
                -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" `
                -Name "DisableSR" -Value 0 -Force -ErrorAction Stop

            $diskSize  = (Get-PSDrive -Name C).Used + (Get-PSDrive -Name C).Free
            $maxBytes  = [math]::Round($diskSize * 0.05)
            vssadmin resize shadowstorage /For=C: /On=C: /MaxSize="$($maxBytes)B" 2>&1 | Out-Null

            Enable-ComputerRestore -Drive "C:\" -ErrorAction Stop

            Update-Messages "✅ Protección del sistema habilitada al 5%."
        } catch {
            Update-Messages "❌ Error al configurar protección: $($_.Exception.Message)"
            return
        }

        # --- 4) Eliminar restricción de frecuencia de 24h ---
        try {
            Set-ItemProperty `
                -Path "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\SystemRestore" `
                -Name "SystemRestorePointCreationFrequency" `
                -Value 0 -Type DWord -Force -ErrorAction Stop
            Update-Messages "✅ Restricción de frecuencia de 24h eliminada."
        } catch {
            Update-Messages "⚠️ No se pudo modificar la frecuencia: $($_.Exception.Message)"
        }

        # --- 5) Crear punto de restauración ---
        $description = "ORIGINAL - Punto restauración manual " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        $created = $false

        try {
            Update-Messages "Creando punto de restauración: '$description'..."
            Checkpoint-Computer -Description $description `
                -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
            Start-Sleep -Seconds 5
            $created = $true
        } catch {
            Update-Messages "❌ Error al crear punto de restauración: $($_.Exception.Message)"
        }

        # --- 6) Verificar que realmente se creó ---
        if ($created) {
            $found = Get-ComputerRestorePoint |
                Where-Object { $_.Description -eq $description }

            if ($found) {
                $ts = [System.Management.ManagementDateTimeConverter]::ToDateTime($found.CreationTime)
                Update-Messages "✅ Punto creado y verificado."
                Update-Messages "   Descripción : $($found.Description)"
                Update-Messages "   Fecha/Hora  : $($ts.ToString('yyyy-MM-dd HH:mm:ss'))"
                Update-Messages "   Número      : $($found.SequenceNumber)"
            } else {
                Update-Messages "❌ El punto NO aparece en la lista (falló silenciosamente)."
            }
        }

        # --- 7) Resumen de todos los puntos existentes ---
        $allPoints = Get-ComputerRestorePoint
        if ($allPoints) {
            Update-Messages "-----------------------------------------"
            Update-Messages "📋 Puntos de restauración existentes: $($allPoints.Count)"
            $allPoints | Sort-Object SequenceNumber | ForEach-Object {
                $ts = [System.Management.ManagementDateTimeConverter]::ToDateTime($_.CreationTime)
                Update-Messages "   [$($_.SequenceNumber)] $($ts.ToString('yyyy-MM-dd HH:mm:ss')) - $($_.Description)"
            }
            Update-Messages "-----------------------------------------"
        }

        Start-Sleep -Seconds 2
        Clear-Messages
    }
    Executed = $false
}

# ---------------------------------------
# ---------------------------------------
# OK - claude
@{
    Name     = "003 - Desactivar UAC"
    Action   = {
        $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Update-Messages "❌ Error: Este script requiere ejecutarse como administrador."
            Start-Sleep -Seconds 3
            return
        }

        Clear-Messages
        Update-Messages "Iniciando tarea: Desactivar UAC..."

        try {
            $uac = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "EnableLUA" -ErrorAction Stop
            if ($uac.EnableLUA -eq 0) {
                Update-Messages "✅ UAC ya está desactivado."
            } else {
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "EnableLUA" -Value 0 -ErrorAction Stop
                Update-Messages "✅ UAC desactivado. Se requiere reinicio para aplicar."
            }
        } catch {
            Update-Messages "❌ Error al comprobar/desactivar UAC: $($_.Exception.Message)"
        }

        Clear-Messages
    }
    Executed = $false
}

# ---------------------------------------
# ---------------------------------------
# OK - claude
@{
    Name     = "004 - Configurar ajustes avanzados de energía"
    Action   = {

        # --- Funciones locales ---
        function Test-Admin {
            return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).
                   IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        }

        function Exec {
            param([string]$Desc, [scriptblock]$Code)
            try {
                & $Code -ErrorAction Stop
                Update-Messages "✅ $Desc"
            } catch {
                Update-Messages "❌ Error en '$Desc': $($_.Exception.Message)"
            }
        }

        function SetIfDifferent {
            param($scheme, $sub, $setting, $desired, $desc)
            try {
                $current = [int](powercfg -getacvalueindex $scheme $sub $setting 2>$null)
                if ($current -eq $desired) {
                    Update-Messages "✅ $desc ya está configurado en $desired."
                } else {
                    powercfg /setacvalueindex $scheme $sub $setting $desired
                    powercfg /setdcvalueindex $scheme $sub $setting $desired
                    Update-Messages "✅ $desc cambiado de $current a $desired."
                }
            } catch {
                Update-Messages "❌ Error en '$desc': $($_.Exception.Message)"
            }
        }

        # --- Verificación inicial ---
        Clear-Messages
        Update-Messages "Verificando privilegios de administrador..."
        if (-not (Test-Admin)) {
            Update-Messages "❌ ERROR: Ejecuta el script como Administrador."
            return
        }

        # --- Crear o activar plan Máximo rendimiento ---
        Update-Messages "Verificando plan 'Máximo rendimiento'..."
        $maxPerfName = "Máximo rendimiento"
        $output = powercfg /L

        if (-not ($output | Where-Object { $_ -like "*$maxPerfName*" })) {
            powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 | Out-Null
            Update-Messages "✅ Plan 'Máximo rendimiento' creado."
            $output = powercfg /L
        }

        $scheme = ($output | Where-Object { $_ -like "*$maxPerfName*" }) `
            -replace '.*:\s+([a-fA-F0-9\-]+).*', '$1'
        powercfg -SetActive $scheme
        Update-Messages "✅ Plan 'Máximo rendimiento' activado. GUID: $scheme"

        # --- CPU al 100% ---
        Exec "CPU mínimo y máximo al 100% (AC y DC)" {
            SetIfDifferent $scheme SUB_PROCESSOR PROCTHROTTLEMIN 100 "CPU min AC"
            SetIfDifferent $scheme SUB_PROCESSOR PROCTHROTTLEMAX 100 "CPU max AC"
            powercfg /setdcvalueindex $scheme SUB_PROCESSOR PROCTHROTTLEMIN 100
            powercfg /setdcvalueindex $scheme SUB_PROCESSOR PROCTHROTTLEMAX 100
        }

        # --- Turbo Boost ---
        Exec "Activar Turbo Boost (AC y DC)" {
            powercfg -attributes SUB_PROCESSOR PERFBOOSTMODE -ATTRIB_HIDE
            SetIfDifferent $scheme SUB_PROCESSOR PERFBOOSTMODE 1 "Turbo Boost AC"
            powercfg /setdcvalueindex $scheme SUB_PROCESSOR PERFBOOSTMODE 1
        }

        # --- Refrigeración activa ---
        Exec "Activar refrigeración activa (AC y DC)" {
            SetIfDifferent $scheme SUB_PROCESSOR COOLING_POLICY 0 "Refrigeración AC"
            powercfg /setdcvalueindex $scheme SUB_PROCESSOR COOLING_POLICY 0
        }

        # --- Pantalla, disco y suspensión NUNCA ---
        Exec "Pantalla, disco y suspensión: NUNCA apagar (AC y DC)" {
            powercfg /change monitor-timeout-ac 0
            powercfg /change monitor-timeout-dc 0
            powercfg /change disk-timeout-ac 0
            powercfg /change disk-timeout-dc 0
            powercfg /change standby-timeout-ac 0
            powercfg /change standby-timeout-dc 0
        }

        # --- Hibernación desactivada ---
        Exec "Deshabilitar hibernación" {
            powercfg -hibernate off
        }

        # --- Suspensión selectiva USB desactivada ---
        Exec "Deshabilitar suspensión selectiva USB (AC y DC)" {
            $schemeGuid   = (powercfg /GetActiveScheme) -replace '.*GUID:\s+([a-fA-F0-9\-]+).*', '$1'
            $subGroupGuid = "2a737441-1930-4402-8d77-b2bebba308a3"
            $settingGuid  = "4faab71a-92e5-4726-b531-224559672d19"
            powercfg /SETACVALUEINDEX $schemeGuid $subGroupGuid $settingGuid 0
            powercfg /SETDCVALUEINDEX $schemeGuid $subGroupGuid $settingGuid 0
            powercfg /SETACTIVE $schemeGuid
        }

        # --- ASPM PCIe desactivado ---
        Exec "Deshabilitar ASPM PCIe (AC y DC)" {
            SetIfDifferent $scheme SUB_PCIEXPRESS ASPM 0 "ASPM AC"
            powercfg /setdcvalueindex $scheme SUB_PCIEXPRESS ASPM 0
        }

        # --- Brillo adaptativo desactivado ---
        Exec "Desactivar brillo adaptativo (AC y DC)" {
            SetIfDifferent $scheme SUB_VIDEO ADAPTBRIGHT 0 "Brillo adaptativo AC"
            powercfg /setdcvalueindex $scheme SUB_VIDEO ADAPTBRIGHT 0
        }

        # --- Ahorro energético en red desactivado ---
        Exec "Deshabilitar ahorro energético en adaptadores de red" {
            Get-NetAdapter -Physical | ForEach-Object {
                Disable-NetAdapterPowerManagement -Name $_.Name -NoRestart -Confirm:$false -ErrorAction SilentlyContinue
                Update-Messages "   ✅ Red deshabilitada para: $($_.Name)"
            }
        }

        # --- Aplicar cambios ---
        powercfg /SETACTIVE $scheme

        Update-Messages "-----------------------------------------"
        Update-Messages "✅ Todas las configuraciones de energía aplicadas correctamente."
        Update-Messages "-----------------------------------------"
        Start-Sleep -Seconds 2
        Clear-Messages
    }
    Executed = $false
}

# ---------------------------------------  
# ---------------------------------------
# OK - claude
@{
    Name     = "005 - Configurar personalización y sistema"
    Action   = {

        # --- Funciones locales ---
        function Test-Admin {
            return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).
                   IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        }

        function Exec {
            param([string]$Desc, [scriptblock]$Code)
            try {
                & $Code -ErrorAction Stop
                Update-Messages "✅ $Desc"
            } catch {
                Update-Messages "❌ Error en '$Desc': $($_.Exception.Message)"
            }
        }

        function Safe-SetProperty {
            param($Path, $Name, $Value)
            if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
            try {
                Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type DWord -Force -ErrorAction Stop
            } catch {
                Update-Messages "⚠️ No se pudo establecer ${Name} en ${Path}: $($_.Exception.Message)"
            }
        }

        function Restart-Explorer {
            Exec "Reiniciar Explorador de archivos" {
                Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 800
                Start-Process explorer.exe -ErrorAction SilentlyContinue
            }
        }

        # --- Verificación inicial ---
        Clear-Messages
        Update-Messages "Verificando privilegios de administrador..."
        if (-not (Test-Admin)) {
            Update-Messages "❌ ERROR: Ejecuta el script como Administrador."
            return
        }

        # --- Modo oscuro ---
        Exec "Activar modo oscuro" {
            $darkKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
            Set-ItemProperty -Path $darkKey -Name AppsUseLightTheme   -Type DWord -Value 0 -Force
            Set-ItemProperty -Path $darkKey -Name SystemUsesLightTheme -Type DWord -Value 0 -Force
        }

        # --- Barra de tareas: nunca combinar ---
        Exec "Configurar barra de tareas (nunca combinar)" {
            $regPath = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
            Set-ItemProperty -Path "HKCU:\$regPath" -Name TaskbarGlomLevel  -Value 2 -Type DWord -Force
            Set-ItemProperty -Path "HKCU:\$regPath" -Name MMTaskbarGlomLevel -Value 2 -Type DWord -Force

            Get-ChildItem Registry::HKEY_USERS |
                Where-Object { $_.PSChildName -match '^S-1-5-21-' } |
                ForEach-Object {
                    $hivePath = "$($_.PSPath)\$regPath"
                    if (-not (Test-Path $hivePath)) { New-Item -Path $hivePath -Force | Out-Null }
                    Set-ItemProperty -Path $hivePath -Name TaskbarGlomLevel  -Value 2 -Type DWord -Force
                    Set-ItemProperty -Path $hivePath -Name MMTaskbarGlomLevel -Value 2 -Type DWord -Force
                }

            $defaultDat = "$env:SystemDrive\Users\Default\NTUSER.DAT"
            reg load HKLM\TempDefault $defaultDat | Out-Null
            Set-ItemProperty -Path "HKLM:\TempDefault\$regPath" -Name TaskbarGlomLevel  -Value 2 -Type DWord -Force
            Set-ItemProperty -Path "HKLM:\TempDefault\$regPath" -Name MMTaskbarGlomLevel -Value 2 -Type DWord -Force
            reg unload HKLM\TempDefault | Out-Null
        }

        # --- Ocultar botones de barra de tareas ---
        Exec "Ocultar botón de búsqueda, contactos y vista de tareas" {
            $taskbarKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
            Set-ItemProperty -Path $taskbarKey -Name SearchboxTaskbarMode -Type DWord -Value 0 -Force
            Set-ItemProperty -Path $taskbarKey -Name ShowTaskViewButton    -Type DWord -Value 0 -Force
            Set-ItemProperty -Path $taskbarKey -Name PeopleBand            -Type DWord -Value 0 -Force
        }

        # --- Panel de control en iconos grandes ---
        Exec "Configurar Panel de Control a iconos grandes" {
            $key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ControlPanel"
            if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
            Set-ItemProperty -Path $key -Name AllItemsIconView -Type DWord -Value 0 -Force
            Set-ItemProperty -Path $key -Name StartupPage      -Type DWord -Value 1 -Force
        }

        # --- Este Equipo en escritorio ---
        Exec "Crear acceso directo 'Este Equipo' en escritorio" {
            $desktop = [Environment]::GetFolderPath("Desktop")
            $lnkPath = Join-Path $desktop "Este equipo.lnk"
            $shell   = New-Object -ComObject WScript.Shell
            $lnk     = $shell.CreateShortcut($lnkPath)
            $lnk.TargetPath   = "::{20D04FE0-3AEA-1069-A2D8-08002B30309D}"
            $lnk.IconLocation = "imageres.dll,-109"
            $lnk.Save()

            $clsid = '{20D04FE0-3AEA-1069-A2D8-08002B30309D}'
            $keys  = @(
                'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel',
                'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\ClassicStartMenu'
            )
            foreach ($key in $keys) {
                if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
                Set-ItemProperty -Path $key -Name $clsid -Value 1 -Type DWord -Force
            }
        }

        # --- Ocultar News & Interests ---
        Exec "Ocultar News & Interests" {
            $pol      = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"
            $feedsKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds"
            if (-not (Test-Path $pol))      { New-Item -Path $pol      -Force | Out-Null }
            if (-not (Test-Path $feedsKey)) { New-Item -Path $feedsKey -Force | Out-Null }
            Set-ItemProperty -Path $pol      -Name DisableNewsAndInterests    -Type DWord -Value 1 -Force
            Set-ItemProperty -Path $feedsKey -Name ShellFeedsTaskbarViewMode  -Type DWord -Value 2 -Force
        }

        # --- Focus Assist ---
        Exec "Activar Focus Assist (silenciar notificaciones)" {
            $focusKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings"
            Set-ItemProperty -Path $focusKey -Name NOC_GLOBAL_SETTING_TOASTS_ENABLED          -Type DWord -Value 0 -Force
            Set-ItemProperty -Path $focusKey -Name NOC_GLOBAL_SETTING_CRITICAL_TOASTS_ENABLED  -Type DWord -Value 0 -Force
        }

        # --- Botón teclado táctil ---
        Exec "Activar botón del teclado táctil en barra de tareas" {
            Safe-SetProperty 'HKCU:\SOFTWARE\Microsoft\TabletTip\1.7' 'EnableDesktopModeAutoInvoke' 1
            Safe-SetProperty 'HKLM:\SOFTWARE\Microsoft\TabletTip\1.7' 'EnableDesktopModeAutoInvoke' 1
        }

        # --- Borrar notificaciones ---
        Exec "Borrar todas las notificaciones pendientes" {
            $notifPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Data'
            if (Test-Path $notifPath) {
                Remove-Item -Path $notifPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        # --- Desactivar Firewall ---
        Exec "Desactivar Firewall (todos los perfiles)" {
            Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
        }

        # --- Desactivar telemetría ---
        Exec "Deshabilitar DiagTrack (telemetría)" {
            Set-Service  -Name DiagTrack -StartupType Disabled -ErrorAction Stop
            Stop-Service -Name DiagTrack -Force -ErrorAction Stop
        }

        Exec "Deshabilitar dmwappushservice (telemetría)" {
            Set-Service  -Name dmwappushservice -StartupType Disabled -ErrorAction Stop
            Stop-Service -Name dmwappushservice -Force -ErrorAction Stop
        }

        Exec "Forzar AllowTelemetry = 0" {
            $reg = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
            if (-not (Test-Path $reg)) { New-Item -Path $reg -Force | Out-Null }
            Set-ItemProperty -Path $reg -Name AllowTelemetry -Type DWord -Value 0 -Force
        }

        # --- Idioma, región y zona horaria ---
        Exec "Establecer idioma es-ES, teclado y zona horaria" {
            if (Get-Command Install-Language -ErrorAction SilentlyContinue) {
                $langs = Get-WinUserLanguageList
                if ($langs.LanguageTag -notcontains "es-ES") {
                    Install-Language -Language es-ES -Force -ErrorAction Stop
                    $newList = New-WinUserLanguageList -Language 'es-ES'
                    $newList[0].InputMethodTips = '0000040A'
                    Set-WinUserLanguageList -LanguageList $newList -Force -ErrorAction Stop
                } else {
                    Update-Messages "   ✅ Idioma es-ES ya presente."
                }
            } else {
                Update-Messages "   ⚠️ Cmdlets de idioma no disponibles en esta edición."
            }

            tzutil /s "Romance Standard Time"
            Set-WinUILanguageOverride    -Language 'es-ES'
            Set-Culture                  'es-ES'
            Set-WinSystemLocale          'es-ES'
            Set-WinHomeLocation          -GeoId 180
            Set-WinDefaultInputMethodOverride -InputTip '0000040A'

            sc config w32time start= auto | Out-Null
            Start-Service w32time -ErrorAction SilentlyContinue
            w32tm /config /syncfromflags:manual /manualpeerlist:'time.windows.com,pool.ntp.org,time.nist.gov' /update | Out-Null
            w32tm /resync /force | Out-Null
        }

        # --- Reiniciar Explorer para aplicar cambios visuales ---
        Restart-Explorer

        Update-Messages "-----------------------------------------"
        Update-Messages "✅ Todas las configuraciones de personalización aplicadas correctamente."
        Update-Messages "-----------------------------------------"
        Start-Sleep -Seconds 2
        Clear-Messages
    }
    Executed = $false
}

# ---------------------------------------  
# ---------------------------------------
# OK - claude
@{
    Name = "006 - Activar características de Windows"
    Action = {
        Clear-Messages
        Update-Messages "Iniciando activación de características de Windows..."

        function Enable-FeatureSafe {
            param([string]$FeatureName)
            try {
                $feat = Get-WindowsOptionalFeature -Online -FeatureName $FeatureName -ErrorAction Stop
                if ($feat.State -eq 'Enabled') {
                    Update-Messages "✅ ${FeatureName} ya está habilitada."
                } else {
                    Update-Messages "Activando ${FeatureName}..."
                    Write-Host "`n--- Instalando $FeatureName (barra real de Windows) ---" -ForegroundColor Yellow
                    Start-Process -FilePath "cmd.exe" -ArgumentList "/c dism /Online /Enable-Feature /FeatureName:$FeatureName /All /NoRestart" -Wait -NoNewWindow
                    Update-Messages "✅ ${FeatureName} activada correctamente."
                }
            } catch {
                Update-Messages "❌ Error al procesar ${FeatureName}: $($_.Exception.Message)"
            }
        }

        function Check-Net45 {
            try {
                $netRegKey = "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full"
                $version = (Get-ItemProperty -Path $netRegKey -ErrorAction Stop).Version
                if ($version -ge "4.5") {
                    Update-Messages "✅ .NET Framework 4.5+ detectado: Versión $version"
                } else {
                    Update-Messages "❌ .NET Framework 4.5+ NO DETECTADO. Puede requerir actualización del sistema."
                }
            } catch {
                Update-Messages "⚠️ No se pudo leer la versión de .NET Framework."
            }
        }

        $features = @(
            "NetFx3",                 # .NET Framework 3.5
            "NetFx4",                 # .NET Framework 4.x
            "Microsoft-Hyper-V-All",  # Hyper-V
            "SMB1Protocol",           # SMB 1.0
            "TelnetClient"            # Cliente Telnet
        )

        foreach ($f in $features) {
            Enable-FeatureSafe -FeatureName $f
        }

        Update-Messages "Verificando presencia de .NET Framework 4.5+..."
        Check-Net45

        Update-Messages "✅ Proceso completado. Algunas características requieren reinicio."
        $script:ExecutedOptions['06'] = $true
        Start-Sleep -Seconds 2
        Clear-Messages
    }
    Executed = $false
}

# ---------------------------------------  
# ---------------------------------------
# OK - claude
@{
    Name = "007 - Actualización de Windows"
    Action = {
        Clear-Messages

        function Test-Admin {
            return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).
                   IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        }

        function Exec {
            param([string]$Desc, [scriptblock]$Code)
            try {
                & $Code -ErrorAction Stop
                Update-Messages "✅ $Desc"
            } catch {
                Update-Messages "❌ Error en '$Desc': $($_.Exception.Message)"
            }
        }

        function Show-TextBar {
            param([int]$Percent, [string]$Activity)
            $barLength    = 30
            $filledLength = [int]($barLength * $Percent / 100)
            $bar          = "█" * $filledLength + "░" * ($barLength - $filledLength)
            Update-Messages "[${bar}] ${Percent}% - ${Activity}"
        }

        # --- 1) Verificar administrador ---
        Update-Messages "Verificando privilegios de administrador..."
        if (-not (Test-Admin)) {
            Update-Messages "❌ ERROR: Ejecuta el script como Administrador."
            return
        }
        Update-Messages "✅ Ejecutando como administrador."

        # --- 2) Instalar proveedor NuGet si no está ---
        Show-TextBar -Percent 10 -Activity "Verificando proveedor NuGet..."
        Exec "Verificar/Instalar proveedor NuGet" {
            $nuget = Get-PackageProvider -ListAvailable -ErrorAction SilentlyContinue |
                     Where-Object { $_.Name -eq 'NuGet' -and $_.Version -ge '2.8.5.201' }
            if (-not $nuget) {
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
            } else {
                Update-Messages "   ✅ NuGet ya está instalado."
            }
        }

        # --- 3) Instalar PSWindowsUpdate si no está ---
        Show-TextBar -Percent 20 -Activity "Verificando módulo PSWindowsUpdate..."
        Exec "Verificar/Instalar módulo PSWindowsUpdate" {
            if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
                Install-Module -Name PSWindowsUpdate -Force -AllowClobber -Scope CurrentUser | Out-Null
            } else {
                Update-Messages "   ✅ PSWindowsUpdate ya está instalado."
            }
        }

        # --- 4) Importar módulo ---
        Show-TextBar -Percent 30 -Activity "Importando módulo PSWindowsUpdate..."
        Exec "Importar módulo PSWindowsUpdate" {
            Import-Module PSWindowsUpdate -ErrorAction Stop
        }

        # --- 5) Buscar actualizaciones disponibles ---
        Show-TextBar -Percent 40 -Activity "Buscando actualizaciones disponibles..."
        Update-Messages "Buscando actualizaciones, esto puede tardar unos minutos..."

        $updates = $null
        try {
            $updates = Get-WindowsUpdate -AcceptAll -ErrorAction Stop
        } catch {
            Update-Messages "❌ Error al buscar actualizaciones: $($_.Exception.Message)"
            return
        }

        if (-not $updates -or $updates.Count -eq 0) {
            Show-TextBar -Percent 100 -Activity "Sin actualizaciones pendientes."
            Update-Messages "-----------------------------------------"
            Update-Messages "✅ El sistema está completamente actualizado."
            Update-Messages "-----------------------------------------"
            Start-Sleep -Seconds 2
            Clear-Messages
            return
        }

        # --- 6) Mostrar actualizaciones encontradas ---
        Show-TextBar -Percent 50 -Activity "Actualizaciones encontradas: $($updates.Count)"
        Update-Messages "-----------------------------------------"
        Update-Messages "📋 Actualizaciones pendientes: $($updates.Count)"
        $updates | ForEach-Object {
            Update-Messages "   • $($_.Title)"
        }
        Update-Messages "-----------------------------------------"

        # --- 7) Instalar actualizaciones con progreso ---
        Update-Messages "Iniciando instalación..."
        $total   = $updates.Count
        $current = 0

        foreach ($update in $updates) {
            $current++
            $percent = [int](($current / $total) * 100)
            Show-TextBar -Percent $percent -Activity "Instalando ($current/$total): $($update.Title)"

            try {
                Install-WindowsUpdate -KBArticleID $update.KBArticleID `
                    -AcceptAll -ForceInstall -IgnoreReboot -ErrorAction Stop | Out-Null
                Update-Messages "   ✅ Instalado: $($update.Title)"
            } catch {
                Update-Messages "   ❌ Error instalando $($update.Title): $($_.Exception.Message)"
            }
        }

        # --- 8) Verificar si requiere reinicio ---
        Show-TextBar -Percent 100 -Activity "Instalación completada."
        Update-Messages "-----------------------------------------"

        $rebootRequired = (Get-WURebootStatus -Silent -ErrorAction SilentlyContinue)
        if ($rebootRequired) {
            Update-Messages "⚠️  Se requiere REINICIO para completar las actualizaciones."
        } else {
            Update-Messages "✅ No se requiere reinicio."
        }

        Update-Messages "✅ Proceso de actualización completado. ($total actualizaciones instaladas)"
        Update-Messages "-----------------------------------------"

        Start-Sleep -Seconds 2
        Clear-Messages
    }
    Executed = $false
}

# ---------------------------------------  
# ---------------------------------------
# OK - claude
@{
    Name = "008 - Configuración inicial del sistema (001-004, 006)"
    Action = {
        Clear-Messages
        Update-Messages "Iniciando configuración inicial del sistema..."
        Update-Messages "Secuencia: 001 → 002 → 003 → 004 → 006"
        Update-Messages "-----------------------------------------"

        function Show-TextBar {
            param([int]$Percent, [string]$Activity)
            $barLength    = 30
            $filledLength = [int]($barLength * $Percent / 100)
            $bar          = "█" * $filledLength + "░" * ($barLength - $filledLength)
            Update-Messages "[${bar}] ${Percent}% - ${Activity}"
        }

        $secuencia = @(
            @{ Orden = "001"; Desc = "Configurar política de ejecución" },
            @{ Orden = "002"; Desc = "Crear punto de restauración" },
            @{ Orden = "003"; Desc = "Desactivar UAC" },
            @{ Orden = "004"; Desc = "Configurar ajustes avanzados de energía" },
            @{ Orden = "006"; Desc = "Activar características de Windows" }
        )

        $total   = $secuencia.Count
        $current = 0
        $errores = @()

        foreach ($paso in $secuencia) {
            $current++
            $percent = [int](($current / $total) * 100)
            Show-TextBar -Percent $percent -Activity "($current/$total) $($paso.Desc)"

            $cmd = $commands | Where-Object { $_.Name -match "^$($paso.Orden)\s*-" } | Select-Object -First 1

            if ($null -eq $cmd) {
                Update-Messages "   ⚠️ Módulo $($paso.Orden) no encontrado, omitiendo."
                $errores += $paso.Orden
                continue
            }

            try {
                Update-Messages "-----------------------------------------"
                Update-Messages "▶️ Ejecutando: $($cmd.Name)"
                & $cmd.Action
                $cmd.Executed = $true
                Update-Messages "✅ $($paso.Desc) completado."
            } catch {
                Update-Messages "❌ Error en $($paso.Desc): $($_.Exception.Message)"
                $errores += $paso.Orden
            }
        }

        Update-Messages "-----------------------------------------"
        Update-Messages "📋 Resumen de la secuencia:"
        foreach ($paso in $secuencia) {
            if ($errores -contains $paso.Orden) {
                Update-Messages "   ❌ $($paso.Orden) - $($paso.Desc)"
            } else {
                Update-Messages "   ✅ $($paso.Orden) - $($paso.Desc)"
            }
        }
        Update-Messages "-----------------------------------------"

        if ($errores.Count -eq 0) {
            Update-Messages "✅ Configuración inicial completada sin errores."
        } else {
            Update-Messages "⚠️ Completado con $($errores.Count) error(es). Revisa los módulos marcados."
        }

        Start-Sleep -Seconds 2
        Clear-Messages
    }
    Executed = $false
}

# ---------------------------------------
# ---------------------------------------  

# OK - claude
@{
    Name = "009 - Configuración completa del sistema (001-004, 006, 007)"
    Action = {
        Clear-Messages
        Update-Messages "Iniciando configuración completa del sistema..."
        Update-Messages "Secuencia: 001 → 002 → 003 → 004 → 006 → 007"
        Update-Messages "-----------------------------------------"

        function Show-TextBar {
            param([int]$Percent, [string]$Activity)
            $barLength    = 30
            $filledLength = [int]($barLength * $Percent / 100)
            $bar          = "█" * $filledLength + "░" * ($barLength - $filledLength)
            Update-Messages "[${bar}] ${Percent}% - ${Activity}"
        }

        $secuencia = @(
            @{ Orden = "001"; Desc = "Configurar política de ejecución" },
            @{ Orden = "002"; Desc = "Crear punto de restauración" },
            @{ Orden = "003"; Desc = "Desactivar UAC" },
            @{ Orden = "004"; Desc = "Configurar ajustes avanzados de energía" },
            @{ Orden = "006"; Desc = "Activar características de Windows" },
            @{ Orden = "007"; Desc = "Actualización de Windows" }
        )

        $total   = $secuencia.Count
        $current = 0
        $errores = @()

        foreach ($paso in $secuencia) {
            $current++
            $percent = [int](($current / $total) * 100)
            Show-TextBar -Percent $percent -Activity "($current/$total) $($paso.Desc)"

            $cmd = $commands | Where-Object { $_.Name -match "^$($paso.Orden)\s*-" } | Select-Object -First 1

            if ($null -eq $cmd) {
                Update-Messages "   ⚠️ Módulo $($paso.Orden) no encontrado, omitiendo."
                $errores += $paso.Orden
                continue
            }

            try {
                Update-Messages "-----------------------------------------"
                Update-Messages "▶️ Ejecutando: $($cmd.Name)"
                & $cmd.Action
                $cmd.Executed = $true
                Update-Messages "✅ $($paso.Desc) completado."
            } catch {
                Update-Messages "❌ Error en $($paso.Desc): $($_.Exception.Message)"
                $errores += $paso.Orden
            }
        }

        Update-Messages "-----------------------------------------"
        Update-Messages "📋 Resumen de la secuencia:"
        foreach ($paso in $secuencia) {
            if ($errores -contains $paso.Orden) {
                Update-Messages "   ❌ $($paso.Orden) - $($paso.Desc)"
            } else {
                Update-Messages "   ✅ $($paso.Orden) - $($paso.Desc)"
            }
        }
        Update-Messages "-----------------------------------------"

        if ($errores.Count -eq 0) {
            Update-Messages "✅ Configuración completa finalizada sin errores."
        } else {
            Update-Messages "⚠️ Completado con $($errores.Count) error(es). Revisa los módulos marcados."
        }

        Start-Sleep -Seconds 2
        Clear-Messages
    }
    Executed = $false
}

# ---------------------------------------  
# ---------------------------------------
# OK - claude
@{
    Name     = "110 - Instalar Chocolatey"
    Action   = {
        $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Update-Messages "❌ Error: Este script requiere ejecutarse como administrador."
            Start-Sleep -Seconds 3
            return
        }

        Clear-Messages
        Update-Messages "Iniciando tarea: Instalar Chocolatey..."

        $chocoPath = "$env:ProgramData\chocolatey\bin\choco.exe"
        if (-not (Test-Path $chocoPath)) {
            Update-Messages "Chocolatey no detectado. Instalando..."
            Set-ExecutionPolicy Bypass -Scope Process -Force
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
            try {
                Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
                Start-Sleep -Seconds 2
                Update-Messages "✅ Chocolatey instalado correctamente."
            } catch {
                Update-Messages "❌ Error instalando Chocolatey: $($_.Exception.Message)"
            }
        } else {
            Update-Messages "✅ Chocolatey ya está instalado."
        }

        Clear-Messages
    }
    Executed = $false
}

# ---------------------------------------
# ---------------------------------------
# OK - claude
@{
    Name = "111 - Instalar entorno de desarrollo (Node.js, npm, pnpm, Git)"
    Action = {
        Clear-Messages
        Update-Messages "Iniciando instalación de entorno de desarrollo..."

        $chocoPath = "$env:ProgramData\chocolatey\bin\choco.exe"
        if (-not (Test-Path $chocoPath)) {
            Update-Messages "❌ ERROR: Chocolatey no está instalado. Ejecuta primero la opción 110."
            return
        }

        function Show-TextBar {
            param([int]$Percent, [string]$Activity)
            $barLength    = 30
            $filledLength = [int]($barLength * $Percent / 100)
            $bar          = "█" * $filledLength + "░" * ($barLength - $filledLength)
            Update-Messages "[${bar}] ${Percent}% - ${Activity}"
        }

        function Install-Choco {
            param([string]$Nombre, [string]$Paquete, [string]$CheckPath = "")
            $instalado = $false
            if ($CheckPath -and (Test-Path $CheckPath)) {
                $instalado = $true
            } elseif (-not $CheckPath) {
                $result = & "$chocoPath" list --local-only $Paquete 2>$null
                if ($result -match $Paquete) { $instalado = $true }
            }

            if ($instalado) {
                Update-Messages "   ✅ $Nombre ya está instalado."
                return
            }

            Update-Messages "   ⏳ Instalando $Nombre..."
            & "$chocoPath" install $Paquete -y --no-progress 2>&1 | Out-Null

            if ($LASTEXITCODE -eq 0) {
                Update-Messages "   ✅ $Nombre instalado correctamente."
            } else {
                Update-Messages "   ❌ Error instalando $Nombre."
            }

            foreach ($desk in @(
                [Environment]::GetFolderPath("CommonDesktopDirectory"),
                [Environment]::GetFolderPath("Desktop")
            )) {
                Get-ChildItem $desk -Filter "*.lnk" -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -like "*$Nombre*" } |
                    Remove-Item -Force -ErrorAction SilentlyContinue
            }
        }

        # --- 1) Node.js ---
        Show-TextBar -Percent 10 -Activity "Verificando Node.js..."
        Install-Choco -Nombre "Node.js" -Paquete "nodejs-lts" `
            -CheckPath "$env:ProgramFiles\nodejs\node.exe"

        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("Path","User")

        # --- 2) npm ---
        Show-TextBar -Percent 35 -Activity "Actualizando npm a última versión..."
        try {
            $npmVersion = & npm --version 2>$null
            if ($npmVersion) {
                Update-Messages "   ⏳ npm detectado v$npmVersion, actualizando..."
                & npm install -g npm 2>&1 | Out-Null
                $npmVersionNew = & npm --version 2>$null
                Update-Messages "   ✅ npm actualizado a v$npmVersionNew"
            } else {
                Update-Messages "   ❌ npm no detectado tras instalar Node.js."
            }
        } catch {
            Update-Messages "   ❌ Error actualizando npm: $($_.Exception.Message)"
        }

        # --- 3) pnpm ---
        Show-TextBar -Percent 60 -Activity "Verificando pnpm..."
        try {
            $pnpmVersion = & pnpm --version 2>$null
            if ($pnpmVersion) {
                Update-Messages "   ✅ pnpm ya está instalado v$pnpmVersion"
            } else {
                Update-Messages "   ⏳ Instalando pnpm..."
                & npm install -g pnpm 2>&1 | Out-Null
                $pnpmVersionNew = & pnpm --version 2>$null
                Update-Messages "   ✅ pnpm instalado v$pnpmVersionNew"
            }
        } catch {
            Update-Messages "   ❌ Error instalando pnpm: $($_.Exception.Message)"
        }

        # --- 4) Git ---
        Show-TextBar -Percent 80 -Activity "Verificando Git..."
        Install-Choco -Nombre "Git" -Paquete "git" `
            -CheckPath "$env:ProgramFiles\Git\bin\git.exe"

        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("Path","User")

        # --- Resumen ---
        Show-TextBar -Percent 100 -Activity "Instalación completada."
        Update-Messages "-----------------------------------------"
        Update-Messages "📋 Versiones instaladas:"
        try { Update-Messages "   Node.js : $(& node --version 2>$null)" } catch {}
        try { Update-Messages "   npm     : v$(& npm --version 2>$null)" } catch {}
        try { Update-Messages "   pnpm    : v$(& pnpm --version 2>$null)" } catch {}
        try { Update-Messages "   Git     : $(& git --version 2>$null)" } catch {}
        Update-Messages "-----------------------------------------"
        Update-Messages "✅ Entorno de desarrollo instalado correctamente."
        Update-Messages "-----------------------------------------"
        Start-Sleep -Seconds 2
        Clear-Messages
    }
    Executed = $false
}

# ---------------------------------------
# ---------------------------------------
# OK - claude
@{
    Name     = "112 - Instalar Telegram Desktop (Chocolatey)"
    Action   = {
        Clear-Messages
        Update-Messages "Iniciando instalación de Telegram Desktop..."

        $chocoPath = "$env:ProgramData\chocolatey\bin\choco.exe"
        if (-not (Test-Path $chocoPath)) {
            Update-Messages "❌ Error: Chocolatey no está instalado. Ejecuta primero la opción 110."
            return
        }

        try {
            Update-Messages "⏳ Ejecutando: choco install telegram -y"
            & "$chocoPath" install telegram -y --no-progress 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Update-Messages "✅ Telegram instalado correctamente."
            } else {
                Update-Messages "❌ Error al instalar Telegram (código $LASTEXITCODE)."
            }
        } catch {
            Update-Messages "❌ Error al instalar Telegram: $($_.Exception.Message)"
        }

        Start-Sleep -Seconds 2
        Clear-Messages
    }
    Executed = $false
}

# ---------------------------------------
# ---------------------------------------
# OK - claude
@{
    Name     = "113 - Instalar Ollama (Chocolatey)"
    Action   = {
        Clear-Messages
        Update-Messages "Iniciando instalación de Ollama..."

        $chocoPath = "$env:ProgramData\chocolatey\bin\choco.exe"
        if (-not (Test-Path $chocoPath)) {
            Update-Messages "❌ Error: Chocolatey no está instalado. Ejecuta primero la opción 110."
            return
        }

        # Verificar si ya está instalado
        if (Get-Command ollama -ErrorAction SilentlyContinue) {
            Update-Messages "✅ Ollama ya está instalado."
            $version = & ollama --version 2>$null
            Update-Messages "   Versión: $version"
            Start-Sleep -Seconds 2
            Clear-Messages
            return
        }

        try {
            Update-Messages "⏳ Ejecutando: choco install ollama -y"
            & "$chocoPath" install ollama -y --no-progress 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                            [System.Environment]::GetEnvironmentVariable("Path","User")
                Update-Messages "✅ Ollama instalado correctamente."
                $version = & ollama --version 2>$null
                Update-Messages "   Versión: $version"
            } else {
                Update-Messages "❌ Error al instalar Ollama (código $LASTEXITCODE)."
            }
        } catch {
            Update-Messages "❌ Error al instalar Ollama: $($_.Exception.Message)"
        }

        Start-Sleep -Seconds 2
        Clear-Messages
    }
    Executed = $false
}

# ---------------------------------------
# ---------------------------------------
# OK - claude
@{
    Name     = "114 - Descargar GLM-5:cloud"
    Action   = {
        Clear-Messages
        Update-Messages "Iniciando descarga del modelo GLM-5:cloud..."

        # Verificar que Ollama está instalado
        if (-not (Get-Command ollama -ErrorAction SilentlyContinue)) {
            Update-Messages "❌ Ollama no está instalado. Ejecuta primero la opción 113."
            return
        }

        try {
            Update-Messages "⏳ Descargando modelo 'glm4:latest' (esto puede tardar varios minutos)..."
            Update-Messages "   Conectando con Ollama..."
            & ollama pull glm4:latest 2>&1 | ForEach-Object { Update-Messages "   $_" }

            if ($LASTEXITCODE -eq 0) {
                Update-Messages "-----------------------------------------"
                Update-Messages "✅ Modelo 'glm4:latest' descargado correctamente."
                Update-Messages "-----------------------------------------"
            } else {
                Update-Messages "❌ Error al descargar el modelo (código $LASTEXITCODE)."
                Update-Messages "   Verifica tu conexión o el nombre del modelo."
            }
        } catch {
            Update-Messages "❌ Error: $($_.Exception.Message)"
        }

        Start-Sleep -Seconds 2
        Clear-Messages
    }
    Executed = $false
}

# ---------------------------------------
# ---------------------------------------
# OK - claude
@{
    Name   = "115 - Lanzar OpenClaw (Ollama)"
    Action = {
        Clear-Messages
        Update-Messages "Iniciando OpenClaw con Ollama..."

        # Verificar que Ollama está instalado
        if (-not (Get-Command ollama -ErrorAction SilentlyContinue)) {
            Update-Messages "❌ Ollama no está instalado. Ejecuta primero la opción 113."
            return
        }

        try {
            Update-Messages "⏳ Ejecutando: ollama launch openclaw"
            Update-Messages "   Si es la primera vez, Ollama instalará OpenClaw automáticamente."
            Update-Messages "   Sigue las instrucciones en pantalla para configurarlo."
            Update-Messages "-----------------------------------------"
            & ollama launch openclaw
        } catch {
            Update-Messages "❌ Error al lanzar OpenClaw: $($_.Exception.Message)"
        }
    }
    Executed = $false
}

# ---------------------------------------
# ---------------------------------------
# OK - claude
@{
    Name = "117 - Instalación OpenClaw sin lanzar (110-114)"
    Action = {
        Clear-Messages
        Update-Messages "Iniciando instalación completa OpenClaw..."
        Update-Messages "Secuencia: 110 → 111 → 112 → 113 → 114"
        Update-Messages "-----------------------------------------"

        function Show-TextBar {
            param([int]$Percent, [string]$Activity)
            $barLength    = 30
            $filledLength = [int]($barLength * $Percent / 100)
            $bar          = "█" * $filledLength + "░" * ($barLength - $filledLength)
            Update-Messages "[${bar}] ${Percent}% - ${Activity}"
        }

        $secuencia = @(
            @{ Orden = "110"; Desc = "Instalar Chocolatey" },
            @{ Orden = "111"; Desc = "Instalar entorno de desarrollo (Node.js, npm, pnpm, Git)" },
            @{ Orden = "112"; Desc = "Instalar Telegram Desktop" },
            @{ Orden = "113"; Desc = "Instalar Ollama" },
            @{ Orden = "114"; Desc = "Descargar GLM-5:cloud" }
        )

        $total   = $secuencia.Count
        $current = 0
        $errores = @()

        foreach ($paso in $secuencia) {
            $current++
            $percent = [int](($current / $total) * 100)
            Show-TextBar -Percent $percent -Activity "($current/$total) $($paso.Desc)"

            $cmd = $commands | Where-Object { $_.Name -match "^$($paso.Orden)\s*-" } | Select-Object -First 1

            if ($null -eq $cmd) {
                Update-Messages "   ⚠️ Módulo $($paso.Orden) no encontrado, omitiendo."
                $errores += $paso.Orden
                continue
            }

            try {
                Update-Messages "-----------------------------------------"
                Update-Messages "▶️ Ejecutando: $($cmd.Name)"
                & $cmd.Action
                $cmd.Executed = $true
                Update-Messages "✅ $($paso.Desc) completado."
            } catch {
                Update-Messages "❌ Error en $($paso.Desc): $($_.Exception.Message)"
                $errores += $paso.Orden
            }
        }

        Update-Messages "-----------------------------------------"
        Update-Messages "📋 Resumen de la secuencia:"
        foreach ($paso in $secuencia) {
            if ($errores -contains $paso.Orden) {
                Update-Messages "   ❌ $($paso.Orden) - $($paso.Desc)"
            } else {
                Update-Messages "   ✅ $($paso.Orden) - $($paso.Desc)"
            }
        }
        Update-Messages "-----------------------------------------"

        if ($errores.Count -eq 0) {
            Update-Messages "✅ Instalación OpenClaw completada sin errores."
        } else {
            Update-Messages "⚠️ Completado con $($errores.Count) error(es). Revisa los módulos marcados."
        }

        Start-Sleep -Seconds 2
        Clear-Messages
    }
    Executed = $false
}

# ---------------------------------------
# ---------------------------------------
# OK - claude
@{
    Name = "118 - Instalación OpenClaw completa con lanzar (110-115)"
    Action = {
        Clear-Messages
        Update-Messages "Iniciando instalación y lanzamiento completo OpenClaw..."
        Update-Messages "Secuencia: 110 → 111 → 112 → 113 → 114 → 115"
        Update-Messages "-----------------------------------------"

        function Show-TextBar {
            param([int]$Percent, [string]$Activity)
            $barLength    = 30
            $filledLength = [int]($barLength * $Percent / 100)
            $bar          = "█" * $filledLength + "░" * ($barLength - $filledLength)
            Update-Messages "[${bar}] ${Percent}% - ${Activity}"
        }

        $secuencia = @(
            @{ Orden = "110"; Desc = "Instalar Chocolatey" },
            @{ Orden = "111"; Desc = "Instalar entorno de desarrollo (Node.js, npm, pnpm, Git)" },
            @{ Orden = "112"; Desc = "Instalar Telegram Desktop" },
            @{ Orden = "113"; Desc = "Instalar Ollama" },
            @{ Orden = "114"; Desc = "Descargar GLM-5:cloud" },
            @{ Orden = "115"; Desc = "Lanzar OpenClaw" }
        )

        $total   = $secuencia.Count
        $current = 0
        $errores = @()

        foreach ($paso in $secuencia) {
            $current++
            $percent = [int](($current / $total) * 100)
            Show-TextBar -Percent $percent -Activity "($current/$total) $($paso.Desc)"

            $cmd = $commands | Where-Object { $_.Name -match "^$($paso.Orden)\s*-" } | Select-Object -First 1

            if ($null -eq $cmd) {
                Update-Messages "   ⚠️ Módulo $($paso.Orden) no encontrado, omitiendo."
                $errores += $paso.Orden
                continue
            }

            try {
                Update-Messages "-----------------------------------------"
                Update-Messages "▶️ Ejecutando: $($cmd.Name)"
                & $cmd.Action
                $cmd.Executed = $true
                Update-Messages "✅ $($paso.Desc) completado."
            } catch {
                Update-Messages "❌ Error en $($paso.Desc): $($_.Exception.Message)"
                $errores += $paso.Orden
            }
        }

        Update-Messages "-----------------------------------------"
        Update-Messages "📋 Resumen de la secuencia:"
        foreach ($paso in $secuencia) {
            if ($errores -contains $paso.Orden) {
                Update-Messages "   ❌ $($paso.Orden) - $($paso.Desc)"
            } else {
                Update-Messages "   ✅ $($paso.Orden) - $($paso.Desc)"
            }
        }
        Update-Messages "-----------------------------------------"

        if ($errores.Count -eq 0) {
            Update-Messages "✅ Instalación y lanzamiento OpenClaw completados sin errores."
        } else {
            Update-Messages "⚠️ Completado con $($errores.Count) error(es). Revisa los módulos marcados."
        }

        Start-Sleep -Seconds 2
        Clear-Messages
    }
    Executed = $false
}

# ---------------------------------------
# ---------------------------------------
# OK - claude
@{
    Name     = "120 - Instalar Chocolatey"
    Action   = {
        $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Update-Messages "❌ Error: Este script requiere ejecutarse como administrador."
            Start-Sleep -Seconds 3
            return
        }

        Clear-Messages
        Update-Messages "Iniciando tarea: Instalar Chocolatey..."

        $chocoPath = "$env:ProgramData\chocolatey\bin\choco.exe"
        if (-not (Test-Path $chocoPath)) {
            Update-Messages "Chocolatey no detectado. Instalando..."
            Set-ExecutionPolicy Bypass -Scope Process -Force
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
            try {
                Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
                Start-Sleep -Seconds 2
                Update-Messages "✅ Chocolatey instalado correctamente."
            } catch {
                Update-Messages "❌ Error instalando Chocolatey: $($_.Exception.Message)"
            }
        } else {
            Update-Messages "✅ Chocolatey ya está instalado."
        }

        Clear-Messages
    }
    Executed = $false
}

# ---------------------------------------
# ---------------------------------------
# OK - claude
@{
    Name = "121 - Instalar software esencial (con Office 365)"
    Action = {
        Clear-Messages
        Update-Messages "Iniciando instalación de software esencial (con Office 365)..."

        $chocoPath = "$env:ProgramData\chocolatey\bin\choco.exe"
        if (-not (Test-Path $chocoPath)) {
            Update-Messages "❌ ERROR: Chocolatey no está instalado. Ejecuta primero la opción 120."
            return
        }

        function Show-TextBar {
            param([int]$Percent, [string]$Activity)
            $barLength    = 30
            $filledLength = [int]($barLength * $Percent / 100)
            $bar          = "█" * $filledLength + "░" * ($barLength - $filledLength)
            Update-Messages "[${bar}] ${Percent}% - ${Activity}"
        }

        function Install-Choco {
            param([string]$Nombre, [string]$Paquete, [string]$CheckPath = "")
            $instalado = $false
            if ($CheckPath -and (Test-Path $CheckPath)) { $instalado = $true }
            elseif (-not $CheckPath) {
                $result = & "$chocoPath" list --local-only $Paquete 2>$null
                if ($result -match $Paquete) { $instalado = $true }
            }
            if ($instalado) { Update-Messages "   ✅ $Nombre ya está instalado."; return }
            Update-Messages "   ⏳ Instalando $Nombre..."
            & "$chocoPath" install $Paquete -y --no-progress 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Update-Messages "   ✅ $Nombre instalado correctamente."
                foreach ($desk in @(
                    [Environment]::GetFolderPath("CommonDesktopDirectory"),
                    [Environment]::GetFolderPath("Desktop")
                )) {
                    Get-ChildItem $desk -Filter "*.lnk" -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -like "*$Nombre*" } |
                        Remove-Item -Force -ErrorAction SilentlyContinue
                }
            } else {
                Update-Messages "   ❌ Error instalando $Nombre."
            }
        }

        $programas = @(
            @{ Nombre = "7-Zip";                  Paquete = "7zip";                        CheckPath = "$env:ProgramFiles\7-Zip\7z.exe" },
            @{ Nombre = "Adobe Reader DC";         Paquete = "adobereader";                 CheckPath = "" },
            @{ Nombre = "Notepad++";               Paquete = "notepadplusplus";             CheckPath = "$env:ProgramFiles\Notepad++\notepad++.exe" },
            @{ Nombre = "VLC Media Player";        Paquete = "vlc";                         CheckPath = "$env:ProgramFiles\VideoLAN\VLC\vlc.exe" },
            @{ Nombre = "Google Chrome";           Paquete = "googlechrome";                CheckPath = "$env:ProgramFiles\Google\Chrome\Application\chrome.exe" },
            @{ Nombre = "DirectX";                 Paquete = "directx";                     CheckPath = "" },
            @{ Nombre = ".NET Framework 4.x";      Paquete = "dotnetfx";                    CheckPath = "" },
            @{ Nombre = "Lightshot";               Paquete = "lightshot";                   CheckPath = "" },
            @{ Nombre = "Java SE Runtime 64 bits"; Paquete = "temurin17";                   CheckPath = "$env:ProgramFiles\Eclipse Adoptium\jdk-17" },
            @{ Nombre = "Advanced IP Scanner";     Paquete = "advanced-ip-scanner";         CheckPath = "" },
            @{ Nombre = "Office 365";              Paquete = "microsoft-office-deployment"; CheckPath = "" }
        )

        $total = $programas.Count; $current = 0
        foreach ($prog in $programas) {
            $current++
            $percent = [int](($current / $total) * 100)
            Show-TextBar -Percent $percent -Activity "Procesando: $($prog.Nombre)"
            Install-Choco -Nombre $prog.Nombre -Paquete $prog.Paquete -CheckPath $prog.CheckPath
        }

        Show-TextBar -Percent 100 -Activity "Instalación completada."
        Update-Messages "-----------------------------------------"
        Update-Messages "✅ Software esencial (con Office 365) instalado correctamente."
        Update-Messages "-----------------------------------------"
        Start-Sleep -Seconds 2
        Clear-Messages
    }
    Executed = $false
}

# ---------------------------------------
# ---------------------------------------
# OK - claude
@{
    Name = "122 - Instalar software esencial (con LibreOffice)"
    Action = {
        Clear-Messages
        Update-Messages "Iniciando instalación de software esencial (con LibreOffice)..."

        $chocoPath = "$env:ProgramData\chocolatey\bin\choco.exe"
        if (-not (Test-Path $chocoPath)) {
            Update-Messages "❌ ERROR: Chocolatey no está instalado. Ejecuta primero la opción 120."
            return
        }

        function Show-TextBar {
            param([int]$Percent, [string]$Activity)
            $barLength    = 30
            $filledLength = [int]($barLength * $Percent / 100)
            $bar          = "█" * $filledLength + "░" * ($barLength - $filledLength)
            Update-Messages "[${bar}] ${Percent}% - ${Activity}"
        }

        function Install-Choco {
            param([string]$Nombre, [string]$Paquete, [string]$CheckPath = "")
            $instalado = $false
            if ($CheckPath -and (Test-Path $CheckPath)) { $instalado = $true }
            elseif (-not $CheckPath) {
                $result = & "$chocoPath" list --local-only $Paquete 2>$null
                if ($result -match $Paquete) { $instalado = $true }
            }
            if ($instalado) { Update-Messages "   ✅ $Nombre ya está instalado."; return }
            Update-Messages "   ⏳ Instalando $Nombre..."
            & "$chocoPath" install $Paquete -y --no-progress 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Update-Messages "   ✅ $Nombre instalado correctamente."
                foreach ($desk in @(
                    [Environment]::GetFolderPath("CommonDesktopDirectory"),
                    [Environment]::GetFolderPath("Desktop")
                )) {
                    Get-ChildItem $desk -Filter "*.lnk" -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -like "*$Nombre*" } |
                        Remove-Item -Force -ErrorAction SilentlyContinue
                }
            } else {
                Update-Messages "   ❌ Error instalando $Nombre."
            }
        }

        $programas = @(
            @{ Nombre = "7-Zip";                  Paquete = "7zip";                CheckPath = "$env:ProgramFiles\7-Zip\7z.exe" },
            @{ Nombre = "Adobe Reader DC";         Paquete = "adobereader";         CheckPath = "" },
            @{ Nombre = "Notepad++";               Paquete = "notepadplusplus";     CheckPath = "$env:ProgramFiles\Notepad++\notepad++.exe" },
            @{ Nombre = "LibreOffice";             Paquete = "libreoffice-fresh";   CheckPath = "$env:ProgramFiles\LibreOffice\program\soffice.exe" },
            @{ Nombre = "VLC Media Player";        Paquete = "vlc";                 CheckPath = "$env:ProgramFiles\VideoLAN\VLC\vlc.exe" },
            @{ Nombre = "Google Chrome";           Paquete = "googlechrome";        CheckPath = "$env:ProgramFiles\Google\Chrome\Application\chrome.exe" },
            @{ Nombre = "DirectX";                 Paquete = "directx";             CheckPath = "" },
            @{ Nombre = ".NET Framework 4.x";      Paquete = "dotnetfx";            CheckPath = "" },
            @{ Nombre = "Lightshot";               Paquete = "lightshot";           CheckPath = "" },
            @{ Nombre = "Java SE Runtime 64 bits"; Paquete = "temurin17";           CheckPath = "$env:ProgramFiles\Eclipse Adoptium\jdk-17" },
            @{ Nombre = "Advanced IP Scanner";     Paquete = "advanced-ip-scanner"; CheckPath = "" }
        )

        $total = $programas.Count; $current = 0
        foreach ($prog in $programas) {
            $current++
            $percent = [int](($current / $total) * 100)
            Show-TextBar -Percent $percent -Activity "Procesando: $($prog.Nombre)"
            Install-Choco -Nombre $prog.Nombre -Paquete $prog.Paquete -CheckPath $prog.CheckPath
        }

        Show-TextBar -Percent 100 -Activity "Instalación completada."
        Update-Messages "-----------------------------------------"
        Update-Messages "✅ Software esencial (con LibreOffice) instalado correctamente."
        Update-Messages "-----------------------------------------"
        Start-Sleep -Seconds 2
        Clear-Messages
    }
    Executed = $false
}

# ---------------------------------------
# OK - claude
@{
    Name = "130 - Descargar y descomprimir Snappy Driver Installer 7z"
    Action = {
        Clear-Messages
        Update-Messages "Iniciando descarga de Snappy Driver Installer..."

        $url         = "https://driveroff.net/drv/SDI_1.25.3.7z"
        $output7z    = "C:\SDI_1.25.3.7z"
        $extractPath = "C:\SDI_1.25.3"
        $sevenZip    = "$env:ProgramFiles\7-Zip\7z.exe"

        # Verificar 7-Zip
        if (-not (Test-Path $sevenZip)) {
            Update-Messages "❌ 7-Zip no encontrado. Instálalo primero con la opción 121 o 122."
            return
        }

        # PASO 1: Descargar
        if (-not (Test-Path $output7z)) {
            Update-Messages "⏳ Descargando SDI desde $url ..."
            try {
                Invoke-WebRequest -Uri $url -OutFile $output7z -UseBasicParsing -ErrorAction Stop
                Update-Messages "✅ Descarga completada."
            } catch {
                Update-Messages "❌ Error al descargar: $($_.Exception.Message)"
                return
            }
        } else {
            Update-Messages "✅ Archivo ya existe, omitiendo descarga."
        }

        # Validar archivo
        $size = (Get-Item $output7z).Length
        if ($size -lt 1024) {
            Update-Messages "❌ El archivo descargado parece corrupto (${size} bytes)."
            Remove-Item $output7z -Force -ErrorAction SilentlyContinue
            return
        }
        Update-Messages "   Tamaño: $([math]::Round($size/1MB, 2)) MB"

        # PASO 2: Preparar carpeta
        if (Test-Path $extractPath) {
            Remove-Item -Path $extractPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -ItemType Directory -Path $extractPath -Force | Out-Null
        Update-Messages "✅ Carpeta destino lista: $extractPath"

        # PASO 3: Descomprimir
        Update-Messages "⏳ Descomprimiendo..."
        try {
            Start-Process -FilePath $sevenZip `
                -ArgumentList "x `"$output7z`" -o`"$extractPath`" -y" `
                -Wait -NoNewWindow -ErrorAction Stop

            $archivos = Get-ChildItem -Path $extractPath -Recurse -ErrorAction Stop
            if ($archivos.Count -eq 0) {
                Update-Messages "❌ La carpeta de destino está vacía. Descompresión fallida."
                return
            }
            Update-Messages "✅ Descompresión completada. $($archivos.Count) archivos extraídos."
        } catch {
            Update-Messages "❌ Error al descomprimir: $($_.Exception.Message)"
            return
        }

        # PASO 4: Mover el 7z dentro de la carpeta
        try {
            $dest7z = Join-Path $extractPath (Split-Path $output7z -Leaf)
            Move-Item -Path $output7z -Destination $dest7z -Force -ErrorAction Stop
            Update-Messages "✅ Archivo 7z movido a: $dest7z"
        } catch {
            Update-Messages "⚠️ No se pudo mover el archivo 7z: $($_.Exception.Message)"
        }

        Update-Messages "-----------------------------------------"
        Update-Messages "✅ Snappy Driver Installer listo en $extractPath"
        Update-Messages "-----------------------------------------"
        Start-Sleep -Seconds 2
        $script:ExecutedOptions['130'] = $true
        Clear-Messages
    }
    Executed = $false
}

# ---------------------------------------
# OK - claude
@{
    Name = "131 - Mantenimiento completo del sistema DISM y SFC"
    Action = {
        Clear-Messages
        Update-Messages "Iniciando mantenimiento completo del sistema..."

        function Test-Admin {
            return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).
                   IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        }

        function Show-TextBar {
            param([int]$Percent, [string]$Activity)
            $barLength    = 30
            $filledLength = [int]($barLength * $Percent / 100)
            $bar          = "█" * $filledLength + "░" * ($barLength - $filledLength)
            Update-Messages "[${bar}] ${Percent}% - ${Activity}"
        }

        # --- 1) Verificar administrador ---
        if (-not (Test-Admin)) {
            Update-Messages "❌ ERROR: Ejecuta el script como Administrador."
            return
        }

        # --- 2) Detectar SSD vs HDD ---
        $isSSD  = $false
        $tipoDs = "Desconocido"
        try {
            $disk   = Get-Partition -DriveLetter C -ErrorAction Stop | Get-Disk -ErrorAction Stop
            $tipoDs = $disk.MediaType
            switch ($disk.MediaType) {
                'SSD' {
                    $isSSD = $true
                    Update-Messages "✅ Unidad C: es SSD. Se omitirá desfragmentación."
                }
                'HDD' {
                    Update-Messages "✅ Unidad C: es HDD. Desfragmentación permitida."
                }
                default {
                    Update-Messages "⚠️ Tipo de medio desconocido ($tipoDs). Se omitirá desfragmentación por seguridad."
                }
            }
        } catch {
            Update-Messages "⚠️ Error detectando tipo de disco: $($_.Exception.Message). Se omitirá desfragmentación."
        }

        # --- 3) Definir tareas DISM + SFC en orden con dependencias ---
        $errores  = @()
        $saltarRestoreHealth = $false

        # DISM CheckHealth
        Show-TextBar -Percent 10 -Activity "DISM /CheckHealth"
        Update-Messages "-----------------------------------------"
        Update-Messages "⏳ Ejecutando DISM /CheckHealth..."
        try {
            $output = DISM.exe /Online /Cleanup-Image /CheckHealth 2>&1
            $output | ForEach-Object { Update-Messages "   $_" }
            if ($LASTEXITCODE -ne 0) {
                Update-Messages "⚠️ CheckHealth detectó problemas (código $LASTEXITCODE). Continuando con ScanHealth..."
            } else {
                Update-Messages "✅ DISM /CheckHealth completado sin errores."
            }
        } catch {
            Update-Messages "❌ Error en DISM /CheckHealth: $($_.Exception.Message)"
            $errores += "DISM /CheckHealth"
        }

        # DISM ScanHealth
        Show-TextBar -Percent 25 -Activity "DISM /ScanHealth"
        Update-Messages "-----------------------------------------"
        Update-Messages "⏳ Ejecutando DISM /ScanHealth (puede tardar varios minutos)..."
        try {
            $output = DISM.exe /Online /Cleanup-Image /ScanHealth 2>&1
            $output | ForEach-Object { Update-Messages "   $_" }
            if ($LASTEXITCODE -ne 0) {
                Update-Messages "⚠️ ScanHealth detectó componentes dañados (código $LASTEXITCODE). Ejecutando RestoreHealth..."
            } else {
                Update-Messages "✅ DISM /ScanHealth completado. No se detectaron daños."
                $saltarRestoreHealth = $false
            }
        } catch {
            Update-Messages "❌ Error en DISM /ScanHealth: $($_.Exception.Message)"
            $errores += "DISM /ScanHealth"
        }

        # DISM RestoreHealth (siempre se ejecuta, ScanHealth puede no detectar todo)
        Show-TextBar -Percent 45 -Activity "DISM /RestoreHealth"
        Update-Messages "-----------------------------------------"
        Update-Messages "⏳ Ejecutando DISM /RestoreHealth (puede tardar bastante)..."
        try {
            $output = DISM.exe /Online /Cleanup-Image /RestoreHealth 2>&1
            $output | ForEach-Object { Update-Messages "   $_" }
            if ($LASTEXITCODE -ne 0) {
                Update-Messages "❌ RestoreHealth falló (código $LASTEXITCODE)."
                $errores += "DISM /RestoreHealth"
            } else {
                Update-Messages "✅ DISM /RestoreHealth completado correctamente."
            }
        } catch {
            Update-Messages "❌ Error en DISM /RestoreHealth: $($_.Exception.Message)"
            $errores += "DISM /RestoreHealth"
        }

        # DISM StartComponentCleanup
        Show-TextBar -Percent 60 -Activity "DISM /StartComponentCleanup"
        Update-Messages "-----------------------------------------"
        Update-Messages "⏳ Ejecutando DISM /StartComponentCleanup..."
        try {
            $output = DISM.exe /Online /Cleanup-Image /StartComponentCleanup 2>&1
            $output | ForEach-Object { Update-Messages "   $_" }
            if ($LASTEXITCODE -ne 0) {
                Update-Messages "⚠️ StartComponentCleanup finalizó con código $LASTEXITCODE."
            } else {
                Update-Messages "✅ DISM /StartComponentCleanup completado."
            }
        } catch {
            Update-Messages "❌ Error en DISM /StartComponentCleanup: $($_.Exception.Message)"
            $errores += "DISM /StartComponentCleanup"
        }

        # SFC /scannow
        Show-TextBar -Percent 75 -Activity "SFC /scannow"
        Update-Messages "-----------------------------------------"
        Update-Messages "⏳ Ejecutando SFC /scannow (puede tardar varios minutos)..."
        try {
            $output = sfc.exe /scannow 2>&1
            $output | ForEach-Object { Update-Messages "   $_" }
            if ($LASTEXITCODE -ne 0) {
                Update-Messages "⚠️ SFC detectó o no pudo reparar algunos archivos (código $LASTEXITCODE)."
                $errores += "SFC /scannow"
            } else {
                Update-Messages "✅ SFC /scannow completado. No se encontraron archivos dañados."
            }
        } catch {
            Update-Messages "❌ Error en SFC /scannow: $($_.Exception.Message)"
            $errores += "SFC /scannow"
        }

        # Desfragmentación solo si es HDD
        if (-not $isSSD -and $tipoDs -ne "Desconocido") {
            Show-TextBar -Percent 90 -Activity "Desfragmentando disco C:"
            Update-Messages "-----------------------------------------"
            Update-Messages "⏳ Ejecutando desfragmentación de C:..."
            try {
                $output = defrag.exe C: /U /V 2>&1
                $output | ForEach-Object { Update-Messages "   $_" }
                Update-Messages "✅ Desfragmentación completada."
            } catch {
                Update-Messages "❌ Error en desfragmentación: $($_.Exception.Message)"
                $errores += "Desfragmentación"
            }
        } else {
            Show-TextBar -Percent 90 -Activity "Ejecutando TRIM en SSD..."
            Update-Messages "-----------------------------------------"
            Update-Messages "⏳ Ejecutando TRIM en SSD C:..."
            try {
                Optimize-Volume -DriveLetter C -ReTrim -Verbose -ErrorAction Stop | Out-Null
                Update-Messages "✅ TRIM ejecutado correctamente."
            } catch {
                Update-Messages "⚠️ No se pudo ejecutar TRIM: $($_.Exception.Message)"
            }
        }

        # --- 4) Resumen final ---
        Show-TextBar -Percent 100 -Activity "Mantenimiento completado."
        Update-Messages "-----------------------------------------"
        Update-Messages "📋 Resumen del mantenimiento:"
        $tareas = @(
            "DISM /CheckHealth",
            "DISM /ScanHealth", 
            "DISM /RestoreHealth",
            "DISM /StartComponentCleanup",
            "SFC /scannow"
        )
        foreach ($tarea in $tareas) {
            if ($errores -contains $tarea) {
                Update-Messages "   ❌ $tarea"
            } else {
                Update-Messages "   ✅ $tarea"
            }
        }
        Update-Messages "-----------------------------------------"

        if ($errores.Count -eq 0) {
            Update-Messages "✅ Mantenimiento completado sin errores."
        } else {
            Update-Messages "⚠️ Completado con $($errores.Count) error(es). Revisa los pasos marcados."
            Update-Messages "   💡 Si SFC falló tras RestoreHealth, prueba a reiniciar y ejecutar de nuevo."
        }

        $script:ExecutedOptions['131'] = $true
        Start-Sleep -Seconds 2
        Clear-Messages
    }
    Executed = $false
}

# --------------------------------------- 
# OK
# Coloca esto al principio de tu script, solo una vez:
@{
    Name = "132 - Limpieza avanzada de disco, archivos temporales y puntos de restauración (mejorado)"
    Action = {
        Clear-Messages
        Update-Messages "Iniciando limpieza avanzada del sistema..."

        function Test-Admin {
            return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).
                   IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        }

        function Show-TextBar {
            param([int]$Percent, [string]$Activity)
            $barLength    = 30
            $filledLength = [int]($barLength * $Percent / 100)
            $bar          = "█" * $filledLength + "░" * ($barLength - $filledLength)
            Update-Messages "[${bar}] ${Percent}% - ${Activity}"
        }

        $MeasureDrive = ($env:SystemDrive).TrimEnd('\').TrimEnd(':')

        function Get-FreeSpaceGB {
            param([string]$DriveLetter = $MeasureDrive)
            try {
                $dl  = $DriveLetter.TrimEnd('\').TrimEnd(':')
                $drv = Get-PSDrive -Name $dl -ErrorAction Stop
                return [math]::Round(($drv.Free / 1GB), 2)
            } catch {
                return $null
            }
        }

        function Exec {
            param([string]$Desc, [scriptblock]$Code)
            try {
                $before = Get-FreeSpaceGB
                & $Code -ErrorAction Stop
                Start-Sleep -Milliseconds 300
                $after = Get-FreeSpaceGB
                if ($before -ne $null -and $after -ne $null) {
                    $delta = [math]::Round(($after - $before), 2)
                    if ($delta -lt 0) { $delta = 0 }
                    Update-Messages "   ✅ $Desc (Liberado: ${delta} GB)"
                } else {
                    Update-Messages "   ✅ $Desc"
                }
            } catch {
                Update-Messages "   ❌ Error en '$Desc': $($_.Exception.Message)"
            }
        }

        # --- Verificar administrador ---
        if (-not (Test-Admin)) {
            Update-Messages "❌ ERROR: Ejecuta el script como Administrador."
            return
        }

        # --- Espacio inicial ---
        $globalBefore = Get-FreeSpaceGB
        Update-Messages "-----------------------------------------"
        Update-Messages "📋 Espacio libre inicial en C: ${globalBefore} GB"
        Update-Messages "-----------------------------------------"

        # --- 1) Temporales de usuarios ---
        Show-TextBar -Percent 8 -Activity "Limpiando temporales de usuarios..."
        Exec "Eliminar temporales de usuarios (AppData\Local\Temp, INetCache)" {
            $excluded = @('All Users','Default','Default User','Public')
            Get-ChildItem C:\Users -Directory -ErrorAction SilentlyContinue |
                Where-Object { $excluded -notcontains $_.Name } |
                ForEach-Object {
                    $userPath  = $_.FullName
                    $tempPaths = @(
                        "$userPath\AppData\Local\Temp\*",
                        "$userPath\AppData\Local\Microsoft\Windows\INetCache\*",
                        "$userPath\AppData\Local\Microsoft\Windows\WER\*",
                        "$userPath\AppData\Local\CrashDumps\*"
                    )
                    foreach ($path in $tempPaths) {
                        if (Test-Path $path) {
                            Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
                        }
                    }
                }
        }

        # --- 2) Temporales del sistema ---
        Show-TextBar -Percent 16 -Activity "Limpiando temporales del sistema..."
        Exec "Eliminar archivos temporales del sistema (Temp, Prefetch, ThumbCache)" {
            $systemPaths = @(
                'C:\Windows\Temp\*',
                "$env:LocalAppData\Temp\*",
                'C:\Windows\Prefetch\*',
                "$env:LocalAppData\Microsoft\Windows\Explorer\thumbcache_*.db",
                'C:\Windows\Downloaded Program Files\*',
                'C:\Windows\SoftwareDistribution\DeliveryOptimization\*'
            )
            foreach ($path in $systemPaths) {
                if (Test-Path $path) {
                    Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }

        # --- 3) Papelera de reciclaje ---
        Show-TextBar -Percent 24 -Activity "Vaciando papelera de reciclaje..."
        Exec "Vaciar la Papelera de reciclaje" {
            try {
                Clear-RecycleBin -Force -ErrorAction Stop
            } catch {
                try {
                    $shell      = New-Object -ComObject Shell.Application
                    $recycleBin = $shell.Namespace(10)
                    if ($recycleBin) {
                        $recycleBin.Items() | ForEach-Object {
                            Remove-Item $_.Path -Recurse -Force -ErrorAction SilentlyContinue
                        }
                    }
                } catch { }
            }
        }

        # --- 4) Caché de navegadores ---
        Show-TextBar -Percent 32 -Activity "Limpiando caché de navegadores..."
        Exec "Limpiar caché de navegadores (Chrome, Edge, Firefox)" {
            $excluded = @('All Users','Default','Default User','Public')
            Get-ChildItem C:\Users -Directory -ErrorAction SilentlyContinue |
                Where-Object { $excluded -notcontains $_.Name } |
                ForEach-Object {
                    $u     = $_.FullName
                    $paths = @(
                        "$u\AppData\Local\Google\Chrome\User Data\Default\Cache\*",
                        "$u\AppData\Local\Google\Chrome\User Data\Default\Code Cache\*",
                        "$u\AppData\Local\Google\Chrome\User Data\Default\GPUCache\*",
                        "$u\AppData\Local\Microsoft\Edge\User Data\Default\Cache\*",
                        "$u\AppData\Local\Microsoft\Edge\User Data\Default\Code Cache\*",
                        "$u\AppData\Local\Microsoft\Edge\User Data\Default\GPUCache\*",
                        "$u\AppData\Local\Mozilla\Firefox\Profiles\*\cache2\*",
                        "$u\AppData\Local\Mozilla\Firefox\Profiles\*\startupCache\*"
                    )
                    foreach ($p in $paths) {
                        if (Test-Path $p) {
                            Remove-Item -Path $p -Recurse -Force -ErrorAction SilentlyContinue
                        }
                    }
                }
        }

        # --- 5) Caché de Windows Defender ---
        Show-TextBar -Percent 40 -Activity "Limpiando caché de Windows Defender..."
        Exec "Limpiar caché de Windows Defender" {
            $defPaths = @(
                "$env:ProgramData\Microsoft\Windows Defender\Scans\History\*",
                "$env:ProgramData\Microsoft\Windows Defender\Support\*"
            )
            foreach ($p in $defPaths) {
                if (Test-Path $p) {
                    Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }

        # --- 6) SoftwareDistribution y logs de Windows Update ---
        Show-TextBar -Percent 50 -Activity "Limpiando SoftwareDistribution..."
        Exec "Limpiar SoftwareDistribution y logs de Windows Update" {
            $services = 'wuauserv','bits','trustedinstaller'
            Get-Service $services -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_.Status -ne 'Stopped') {
                    Stop-Service $_.Name -Force -ErrorAction SilentlyContinue
                }
            }
            Start-Sleep -Milliseconds 500

            $paths = @(
                'C:\Windows\SoftwareDistribution\Download\*',
                'C:\Windows\SoftwareDistribution\DataStore\*',
                'C:\Windows\Logs\CBS\*',
                'C:\$Windows.~BT\*',
                'C:\$Windows.~WS\*'
            )
            foreach ($path in $paths) {
                if (Test-Path $path) {
                    takeown /F $path /R /D Y 2>&1 | Out-Null
                    icacls $path /grant Administrators:F /T 2>&1 | Out-Null
                    Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
                }
            }

            Get-Service $services -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_.Status -ne 'Running') {
                    Start-Service $_.Name -ErrorAction SilentlyContinue
                }
            }
        }

        # --- 7) Logs de eventos ---
        Show-TextBar -Percent 60 -Activity "Borrando registros de eventos..."
        Exec "Borrar registros de eventos de Windows" {
            $logs = wevtutil el 2>$null
            foreach ($log in $logs) {
                try { wevtutil cl $log 2>&1 | Out-Null } catch { }
            }
        }

        # --- 8) Caché de Microsoft Store ---
        Show-TextBar -Percent 68 -Activity "Limpiando caché de Microsoft Store..."
        Exec "Limpiar caché de Microsoft Store (wsreset)" {
            Start-Process -FilePath "wsreset.exe" -Wait -NoNewWindow -ErrorAction SilentlyContinue
        }

        # --- 9) DISM Component Store ---
        Show-TextBar -Percent 76 -Activity "Limpieza de Component Store con DISM..."
        Exec "Limpieza de Component Store con DISM (StartComponentCleanup / ResetBase)" {
            $output = DISM.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase /Quiet 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "DISM finalizó con código $LASTEXITCODE"
            }
        }

        # --- 10) Puntos de restauración antiguos (conservar el más reciente) ---
        Show-TextBar -Percent 86 -Activity "Eliminando puntos de restauración antiguos..."
        Exec "Eliminar puntos de restauración antiguos (conservar el más reciente)" {
            $allPoints = Get-ComputerRestorePoint -ErrorAction SilentlyContinue
            if ($allPoints -and $allPoints.Count -gt 1) {
                $sorted   = $allPoints | Sort-Object SequenceNumber
                $toDelete = $sorted[0..($sorted.Count - 2)]
                foreach ($point in $toDelete) {
                    $ts = [System.Management.ManagementDateTimeConverter]::ToDateTime($point.CreationTime)
                    vssadmin delete shadows /Shadow={$point.ShadowID} /Quiet 2>&1 | Out-Null
                    Update-Messages "   🗑️ Eliminado: [$($point.SequenceNumber)] $($ts.ToString('yyyy-MM-dd HH:mm:ss')) - $($point.Description)"
                }
                $last = $sorted[-1]
                $tsL  = [System.Management.ManagementDateTimeConverter]::ToDateTime($last.CreationTime)
                Update-Messages "   ✅ Conservado: [$($last.SequenceNumber)] $($tsL.ToString('yyyy-MM-dd HH:mm:ss')) - $($last.Description)"
            } elseif ($allPoints -and $allPoints.Count -eq 1) {
                Update-Messages "   ℹ️ Solo hay un punto de restauración, no se elimina nada."
            } else {
                Update-Messages "   ℹ️ No hay puntos de restauración para eliminar."
            }
        }

        # --- 11) Optimizar disco ---
        Show-TextBar -Percent 94 -Activity "Optimizando disco C:..."
        Exec "Optimizar volumen del sistema (TRIM o defrag según corresponda)" {
            Optimize-Volume -DriveLetter $MeasureDrive -Verbose -ErrorAction Stop | Out-Null
        }

        # --- Resumen final ---
        $globalAfter = Get-FreeSpaceGB
        Show-TextBar -Percent 100 -Activity "Limpieza completada."
        Update-Messages "-----------------------------------------"
        if ($globalBefore -ne $null -and $globalAfter -ne $null) {
            $totalLiberado = [math]::Round(($globalAfter - $globalBefore), 2)
            Update-Messages "📋 Espacio libre inicial : ${globalBefore} GB"
            Update-Messages "📋 Espacio libre final   : ${globalAfter} GB"
            Update-Messages "✅ Espacio total liberado : ${totalLiberado} GB"
        } else {
            Update-Messages "✅ Limpieza avanzada completada."
        }
        Update-Messages "-----------------------------------------"

        $script:ExecutedOptions['132'] = $true
        Start-Sleep -Seconds 2
        Clear-Messages
    }
    Executed = $false
}

# --------------------------------------- 

@{
    Name = "150 - Activar Windows";
    Action = {
        Clear-Messages
        Update-Messages "Iniciando activación de Windows..."
        
        # Mostrar opciones al usuario en una sola línea
        $optionsMessage = @"
Seleccione la versión de Windows para activar:
01 - Windows 10
02 - Windows 11
03 - Windows LTSC
04 - Salir al menú principal
"@
        Update-Messages $optionsMessage
        
        # Solicitar al usuario que seleccione una opción
        $choice = Read-Host "Ingrese el número de la opción (01, 02, 03 o 04)"
        
        # Realizar la activación o salir según la opción seleccionada
        switch ($choice) {
            "01" {
                Update-Messages "⏳ Activando Windows 10..."
                try {
                    slmgr /ipk W269N-WFGWX-YVC9B-4J6C9-T83GX
                    slmgr /skms kms.digiboy.ir
                    slmgr /ato
                    Update-Messages "✅ Windows 10 activado correctamente."
                } catch {
                    Update-Messages "❌ Error al activar Windows 10: $($_.Exception.Message)"
                }
            }
            "02" {
                Update-Messages "⏳ Activando Windows 11..."
                try {
                    slmgr /ipk W269N-WFGWX-YVC9B-4J6C9-T83GX
                    slmgr /skms kms.digiboy.ir
                    slmgr /ato
                    Update-Messages "✅ Windows 11 activado correctamente."
                } catch {
                    Update-Messages "❌ Error al activar Windows 11: $($_.Exception.Message)"
                }
            }
            "03" {
                Update-Messages "⏳ Activando Windows LTSC..."
                try {
                    slmgr /ipk M7XTQ-FN8P6-TTKYV-9D4CC-J462D
                    slmgr /skms kms.digiboy.ir
                    slmgr /ato
                    Update-Messages "✅ Windows LTSC activado correctamente."
                } catch {
                    Update-Messages "❌ Error al activar Windows LTSC: $($_.Exception.Message)"
                }
            }
            "04" {
                Update-Messages "Saliendo al menú principal..."
                Start-Sleep -Seconds 2
                Clear-Messages
                return
            }
            default {
                Update-Messages "❌ Opción no válida. Por favor, seleccione una opción válida."
            }
        }
        
        # Mensaje final y regresar al menú principal
        Update-Messages "✅ Proceso de activación completado."
        Start-Sleep -Seconds 2
        Clear-Messages
    };
    Executed = $false
}

# --------------------------------------- 

# OK - claude
@{
    Name = "260 - Reiniciar la cola de impresión";
    Action = {
        Clear-Messages
        Update-Messages "Iniciando el reinicio de la cola de impresión..."

        # Helper genérico para pasos con mensajes y errores
        function Exec {
            param([string]$Desc, [scriptblock]$Code)
            Update-Messages "⏳ $Desc..."
            try {
                & $Code
                Update-Messages "✅ $Desc completado."
            } catch {
                Update-Messages "❌ Error en '$Desc': $($_.Exception.Message)"
            }
        }

        # 1) Detener el servicio de cola de impresión
        Exec "Detener servicio Spooler" {
            Stop-Service -Name Spooler -Force -ErrorAction Stop
        }

        # 2) Vaciar carpeta de trabajos pendientes
        Exec "Eliminar trabajos pendientes" {
            $spoolPath = "$env:windir\System32\spool\PRINTERS"
            if (Test-Path $spoolPath) {
                # Tomar propiedad y permisos para asegurar eliminación
                takeown /F $spoolPath /R /D Y | Out-Null
                icacls $spoolPath /grant Administrators:F /T | Out-Null
                Remove-Item -Path "$spoolPath\*.*" -Recurse -Force -ErrorAction Stop
            } else {
                throw "Ruta de spool no encontrada: $spoolPath"
            }
        }

        # 3) Iniciar el servicio de cola de impresión
        Exec "Iniciar servicio Spooler" {
            Start-Service -Name Spooler -ErrorAction Stop
        }

        Update-Messages "✅ Cola de impresión reiniciada correctamente."
        Clear-Messages
        $script:ExecutedOptions['26'] = $true
    };
    Executed = $false
}

# --------------------------------------- 

# OK - claude
@{
    Name = "270 - Verificar la memoria RAM"
    Action = {
        Clear-Messages
        Update-Messages "Iniciando diagnóstico de memoria RAM..."

        function Test-Admin {
            return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).
                   IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        }

        function Exec {
            param([string]$Desc, [scriptblock]$Code)
            Update-Messages "⏳ $Desc..."
            try {
                & $Code
                Update-Messages "✅ $Desc completado."
            } catch {
                Update-Messages "❌ Error en '$Desc': $($_.Exception.Message)"
            }
        }

        # --- 1) Verificar administrador ---
        if (-not (Test-Admin)) {
            Update-Messages "❌ ERROR: Ejecuta el script como Administrador."
            return
        }

        # --- 2) Mostrar info de RAM actual ---
        try {
            $ram     = Get-CimInstance -ClassName Win32_PhysicalMemory
            $totalGB = [math]::Round(($ram | Measure-Object -Property Capacity -Sum).Sum / 1GB, 2)
            Update-Messages "-----------------------------------------"
            Update-Messages "📋 RAM instalada actualmente:"
            Update-Messages "   Total: $totalGB GB"
            $ram | ForEach-Object {
                Update-Messages "   Banco: $($_.BankLabel) | $([math]::Round($_.Capacity/1GB,0)) GB | $($_.Speed) MHz | $($_.Manufacturer)"
            }
            Update-Messages "-----------------------------------------"
        } catch {
            Update-Messages "⚠️ No se pudo obtener información de RAM: $($_.Exception.Message)"
        }

        # --- 3) Mostrar resultados del último diagnóstico si existen ---
        try {
            $eventos = Get-WinEvent -LogName "System" -ErrorAction Stop |
                Where-Object { $_.ProviderName -eq "Microsoft-Windows-MemoryDiagnostics-Results" } |
                Select-Object -First 1

            if ($eventos) {
                Update-Messages "-----------------------------------------"
                Update-Messages "📋 Último diagnóstico de RAM ejecutado:"
                Update-Messages "   Fecha  : $($eventos.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'))"
                Update-Messages "   Resultado: $($eventos.Message)"
                Update-Messages "-----------------------------------------"
            } else {
                Update-Messages "ℹ️ No se encontraron diagnósticos previos de RAM."
            }
        } catch {
            Update-Messages "ℹ️ No se encontraron diagnósticos previos de RAM."
        }

        # --- 4) Programar diagnóstico via BCDEdit ---
        $bcdeditOk = $false
        Exec "Programar Windows Memory Diagnostic en arranque" {
            $result = bcdedit /bootsequence "{memdiag}" 2>&1
            if ($LASTEXITCODE -eq 0) {
                $bcdeditOk = $true
            } else {
                throw "BCDEdit falló: $result"
            }
        }

        # --- 5) Verificar que quedó configurado ---
        if ($bcdeditOk) {
            Exec "Verificar configuración de arranque" {
                $seq = bcdedit /enum "{current}" 2>&1 | Select-String "bootsequence"
                if ($seq -and $seq -match "{memdiag}") {
                    Update-Messages "   ✅ {memdiag} confirmado en bootsequence."
                } else {
                    throw "No se encontró {memdiag} en bootsequence."
                }
            }
        } else {
            # Fallback SOLO si BCDEdit falló
            Update-Messages "⚠️ BCDEdit falló, usando registro como alternativa..."
            try {
                $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
                $current = (Get-ItemProperty -Path $regPath -Name BootExecute).BootExecute
                if ($current -notcontains "memdiag") {
                    Set-ItemProperty -Path $regPath -Name BootExecute `
                        -Value ($current + "memdiag") -Force
                    Update-Messages "✅ Diagnóstico programado via registro."
                } else {
                    Update-Messages "✅ Diagnóstico ya estaba programado via registro."
                }
            } catch {
                Update-Messages "❌ Error en fallback: $($_.Exception.Message)"
            }
        }

        # --- 6) Preguntar si reiniciar ahora ---
        Update-Messages "-----------------------------------------"
        Update-Messages "⚠️  El diagnóstico requiere reinicio para ejecutarse."
        Update-Messages "-----------------------------------------"
        $respuesta = Read-Host "¿Deseas reiniciar ahora para ejecutar la prueba? (S/N)"

        if ($respuesta -eq "S" -or $respuesta -eq "s") {
            Update-Messages "⏳ Reiniciando el equipo en 10 segundos..."
            Update-Messages "   Cierra cualquier aplicación abierta."
            Start-Sleep -Seconds 10
            Restart-Computer -Force -Confirm:$false
        } else {
            Update-Messages "-----------------------------------------"
            Update-Messages "ℹ️  El diagnóstico se ejecutará en el próximo reinicio."
            Update-Messages "   Los resultados estarán en el Visor de eventos:"
            Update-Messages "   📁 Registros de Windows → Sistema → MemoryDiagnostics-Results"
            Update-Messages "-----------------------------------------"
        }

        Start-Sleep -Seconds 2
        Clear-Messages
        $script:ExecutedOptions['270'] = $true
    }
    Executed = $false
}

# ---------------------------------------
# OK - claude
# OK - claude
@{
    Name = "300 - Crear impresoras genéricas BARRA y COCINA";
    Action = {
        Clear-Messages
        Update-Messages "Iniciando creación de impresoras genéricas..."

        try {
            # Datos para las impresoras
            $printers = @(
                @{ Name = "BARRA"; Port = "LPT3:" },
                @{ Name = "COCINA"; Port = "LPT2:" }
            )
            $driverName = "Generic / Text Only"

            # Procesar cada impresora
            foreach ($printer in $printers) {
                # Verificar si el puerto ya existe
                if (-not (Get-PrinterPort -Name $printer.Port -ErrorAction SilentlyContinue)) {
                    Update-Messages "⏳ Creando puerto: $($printer.Port)..."
                    Add-PrinterPort -Name $printer.Port
                    Update-Messages "✅ Puerto $($printer.Port) creado correctamente."
                } else {
                    Update-Messages "✅ Puerto $($printer.Port) ya existe."
                }

                # Verificar si el controlador genérico está instalado
                if (-not (Get-PrinterDriver -Name $driverName -ErrorAction SilentlyContinue)) {
                    Update-Messages "⏳ Instalando controlador genérico: $driverName..."
                    Add-PrinterDriver -Name $driverName
                    Update-Messages "✅ Controlador genérico instalado correctamente."
                } else {
                    Update-Messages "✅ Controlador $driverName ya está instalado."
                }

                # Crear la impresora
                Update-Messages "⏳ Creando impresora $($printer.Name) en $($printer.Port)..."
                Add-Printer -Name $printer.Name -DriverName $driverName -PortName $printer.Port
                Update-Messages "✅ Impresora $($printer.Name) creada correctamente."
            }

        } catch {
            Update-Messages "❌ Error durante la creación de las impresoras: $($_.Exception.Message)"
        }

        Clear-Messages
        $script:ExecutedOptions['30'] = $true
    };
    Executed = $false
}

# ---------------------------------------
# OK - claude
@{
    Name = "990 - Salir"
    Action = {
        Clear-Messages
        Update-Messages "Saliendo del menú..."
        Start-Sleep -Seconds 1
        exit
    }
    Executed = $false
}
)

# ---------------------------------------

# Variables globales para los mensajes
$global:messages = @()
$global:menuDisplayed = $false

# ---------------------------------------
function Show-Menu {
    cls
    Write-Host "=========== Menú Principal ===========" -ForegroundColor Cyan
    foreach ($command in $commands) {
        if ($command.Executed) {
            Write-Host $command.Name -ForegroundColor Green
        } elseif ($command.Name -like "10*") {
            Write-Host $command.Name -ForegroundColor Red  # Color rojo para la opción 10
        } else {
            Write-Host $command.Name -ForegroundColor Yellow
        }

                # Separadores específicos
        if ($command.Name -like "009*") {
            Write-Host "======================================" -ForegroundColor Blue
        }
        if ($command.Name -like "118*") {
            Write-Host "======================================" -ForegroundColor Blue
        }
        if ($command.Name -like "122*") {
            Write-Host "======================================" -ForegroundColor Blue
        }
        if ($command.Name -like "132*") {
            Write-Host "======================================" -ForegroundColor Blue
if ($command.Name -like "150*") {
            Write-Host "======================================" -ForegroundColor Blue
        }
        }
        if ($command.Name -like "26*") {
            Write-Host "======================================" -ForegroundColor Blue
        }
        if ($command.Name -like "27*") {
            Write-Host "======================================" -ForegroundColor Blue
        }
        if ($command.Name -like "30*") {
            Write-Host "======================================" -ForegroundColor Blue
        }
    }
    Write-Host "======================================"
    Write-Host ""
}



# ---------------------------------------

# Función para actualizar los mensajes
function Update-Messages {
    param (
        [string]$Message
    )
    $global:messages += $Message
    foreach ($msg in $global:messages) {
        Write-Host $msg
    }
}
# ---------------------------------------

# Función para limpiar los mensajes
function Clear-Messages {
    $global:messages = @()
    Show-Menu
}
# ---------------------------------------

# ---------------------------------------

# Función principal del menú
function Main-Menu {
    while ($true) {
        Show-Menu
        $choice = Read-Host "Selecciona una opción"

        # Buscar el comando seleccionado
        $selectedCommand = $commands | Where-Object { $_.Name -like "$choice*" }
        if ($selectedCommand) {
            $selectedCommand.Executed = $true
            & $selectedCommand.Action
        } else {
            Clear-Messages
            Update-Messages "Opción inválida, intenta nuevamente."
        }
    }
}
# ---------------------------------------

# Ejecutar el menú
Main-Menu
# ---------------------------------------

# Fin del script