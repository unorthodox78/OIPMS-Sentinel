$ErrorActionPreference = 'Stop'
$path = 'c:\Users\jomar\AndroidStudioProjects\OIP_Sentinel\lib\screens\production_tab.dart'
$backup = "$path.bak_$(Get-Date -Format yyyyMMdd_HHmmss)"
Copy-Item -Path $path -Destination $backup -Force

$content = Get-Content -Path $path -Raw

# Replace popup Type cell Text with icon+text Row
$pattern1 = '(?s)DataCell\(\s*Text\(\s*row\[''type''\]\.toString\(\),\s*style:\s*const\s*TextStyle\(\s*color:\s*Colors\.black87\s*\),\s*\),\s*\),'
$replacement1 = @"
DataCell(
  Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Image.asset(
        row['type'].toString().contains('Cube')
            ? 'assets/cube.png'
            : 'assets/ice_block.png',
        width: 20,
        height: 20,
        filterQuality: FilterQuality.high,
      ),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          row['type'].toString(),
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.black87),
        ),
      ),
    ],
  ),
),
"@

$newContent = [regex]::Replace($content, $pattern1, $replacement1)

# Replace inline Type cell inner Text with icon+text Row
$pattern2 = '(?s)child:\s*Text\(\s*row\[''type''\]\.toString\(\),\s*overflow:\s*TextOverflow\.ellipsis,\s*style:\s*const\s*TextStyle\(\s*color:\s*Colors\.black87,\s*fontWeight:\s*FontWeight\.normal,\s*\),\s*\),'
$replacement2 = @"
child: Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    Image.asset(
      row['type'].toString().contains('Cube')
          ? 'assets/cube.png'
          : 'assets/ice_block.png',
      width: 20,
      height: 20,
      filterQuality: FilterQuality.high,
    ),
    const SizedBox(width: 6),
    Flexible(
      child: Text(
        row['type'].toString(),
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.black87,
          fontWeight: FontWeight.normal,
        ),
      ),
    ),
  ],
),
"@

$newContent = [regex]::Replace($newContent, $pattern2, $replacement2)

if ($newContent -ne $content) {
  Set-Content -Path $path -Value $newContent -Encoding UTF8
  Write-Output "Updated production_tab.dart and created backup: $backup"
} else {
  Write-Output "No changes applied. Patterns not found. Backup created: $backup"
}
