param([Parameter(Mandatory=$true)][string]$Source,[Parameter(Mandatory=$true)][string]$Destination)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression
$root=(Resolve-Path -LiteralPath $Source).Path.TrimEnd('\')
$stream=[IO.File]::Open($Destination,[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::None)
try{
    $archive=New-Object IO.Compression.ZipArchive($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
    try{
        foreach($file in (Get-ChildItem -LiteralPath $root -File -Recurse|Where-Object{$_.Name-notlike '._*'}|Sort-Object FullName)){
            $relative=$file.FullName.Substring($root.Length+1).Replace('\','/')
            $entry=$archive.CreateEntry($relative,[IO.Compression.CompressionLevel]::Optimal)
            $entryStream=$entry.Open();$inputStream=[IO.File]::OpenRead($file.FullName)
            try{$inputStream.CopyTo($entryStream)}finally{$inputStream.Dispose();$entryStream.Dispose()}
        }
    }finally{$archive.Dispose()}
}finally{$stream.Dispose()}
