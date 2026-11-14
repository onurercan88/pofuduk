param([string]$Text, [string]$SaveTo)
# Speaks Turkish text with a Windows tr-TR voice (Pofuduk demo --ses).
# Uses the modern Windows speech API (OneCore voices such as "Microsoft Tolga"), falling back to SAPI.
# Messages are ASCII-only: Windows PowerShell 5.1 reads BOM-less scripts in the ANSI code page.
$ErrorActionPreference = 'Stop'

function Speak-OneCore([string]$text) {
    [void][Windows.Media.SpeechSynthesis.SpeechSynthesizer, Windows.Media.SpeechSynthesis, ContentType = WindowsRuntime]
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $voice = [Windows.Media.SpeechSynthesis.SpeechSynthesizer]::AllVoices | Where-Object { $_.Language -eq 'tr-TR' } | Select-Object -First 1
    if (-not $voice) { return $false }
    $synth = [Windows.Media.SpeechSynthesis.SpeechSynthesizer]::new()
    $synth.Voice = $voice
    $asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } | Select-Object -First 1
    $task = $asTask.MakeGenericMethod([Windows.Media.SpeechSynthesis.SpeechSynthesisStream]).Invoke($null, @($synth.SynthesizeTextToStreamAsync($text)))
    $task.Wait()
    $stream = [System.IO.WindowsRuntimeStreamExtensions]::AsStreamForRead($task.Result)
    if ($SaveTo) {
        $file = [System.IO.File]::Create($SaveTo); $stream.CopyTo($file); $file.Close()
    } else {
        (New-Object System.Media.SoundPlayer($stream)).PlaySync()
    }
    return $true
}

function Speak-Sapi([string]$text) {
    Add-Type -AssemblyName System.Speech
    $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
    $voice = $synth.GetInstalledVoices() | Where-Object { $_.Enabled -and $_.VoiceInfo.Culture.Name -eq 'tr-TR' } | Select-Object -First 1
    if (-not $voice) { return $false }
    $synth.SelectVoice($voice.VoiceInfo.Name)
    $synth.Speak($text)
    return $true
}

$ok = $false
try { $ok = Speak-OneCore $Text } catch { $ok = $false }
if (-not $ok) { try { $ok = Speak-Sapi $Text } catch { $ok = $false } }
if (-not $ok) {
    Write-Host '  (Turkce ses bulunamadi: Ayarlar > Saat ve dil > Konusma > Ses ekle > Turkce. Metin yukarida.)'
}
