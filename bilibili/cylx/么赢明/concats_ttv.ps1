# 设置 ffmpeg 可执行文件路径
$ffmpegPath = "C:\Users\Administrator\scoop\apps\ffmpeg\8.0\bin\ffmpeg.exe"

# 1. 获取当前文件夹的名称
$currentPath = Get-Location
$folderName = Split-Path $currentPath.Path -Leaf

# 2. 【修正 Filter 的使用】: 分别获取 .ts 和 .mp4 文件，然后合并
# 使用 @() 确保数组的创建，即使 Get-ChildItem 没有返回任何结果
$tsAndMp4Files = @(
    Get-ChildItem -Path $currentPath -Filter "*.ts" -Force
    Get-ChildItem -Path $currentPath -Filter "*.mp4" -Force
)

# 过滤掉非文件项，并检查文件名中是否包含日期格式，最后按名称排序（确保时间顺序）
$tsFiles = $tsAndMp4Files | 
    Where-Object { 
        $_.PSIsContainer -eq $false -and $_.Name -match '\d{4}-\d{2}-\d{2}' 
    } | 
    Sort-Object Name 

# 3. 从文件名中提取日期进行分组
# 使用正则表达式可靠地找到 YYYY-MM-DD 模式
$videoFilesByDate = $tsFiles | Group-Object {
    if ($_.Name -match '(\d{4}-\d{2}-\d{2})') {
        # 返回匹配到的 YYYY-MM-DD 作为分组键
        return $Matches[1] 
    }
    return "UnknownDate"
}

# 4. 构造每天的视频文件列表并合并
foreach ($group in $videoFilesByDate) {
    $datePart = $group.Name # 提取出的日期字符串，例如 "2025-11-01"
    $videoFileObjects = $group.Group # 这一天的所有文件对象
    $videoFileNames = $videoFileObjects.Name # 这一天的所有文件名

    # 检查是否有未知日期分组
    if ($datePart -eq "UnknownDate") {
        Write-Warning "Skipping files with unknown date format: $($videoFileNames -join ', ')"
        continue
    }

    # 5. 【ID/系列名称提取逻辑】: 从这一天最早的文件中提取 ID
    # 文件名格式: "ID_YYYY-MM-DD_HH-MM-SS_分段.ts"
    $firstFileName = $videoFileObjects[0].BaseName # 例如：ID_with_underscore_2025-11-01_08-02-51_分段
    
    # 查找日期模式的起始位置：找到第一个下划线后面紧跟着 YYYY-MM-DD 的位置
    if ($firstFileName -match '_(\d{4}-\d{2}-\d{2})') {
        # $Matches.Index 是匹配到的 '_YYYY-MM-DD' 中 '_' 的索引
        $dateIndex = $Matches.Index 
        
        # ID 部分就是从开头到 $dateIndex 之前的所有内容
        $seriesID = $firstFileName.Substring(0, $dateIndex)
        
        # 移除末尾可能多余的下划线
        $seriesID = $seriesID.TrimEnd('_')
        
        # 如果ID为空，给个默认值
        if (-not $seriesID) {
            $seriesID = "Series"
        }
        
    } else {
        # 兜底方案
        $seriesID = "Series"
    }

    # 6. 构造最终的输出文件名：[文件夹名称]-[ID]-[日期].mp4
    $outputFileName = "$($folderName)-$($seriesID)-$($datePart).mp4"
    
    Write-Host "--- Processing Date: $datePart ---"
    Write-Host "Output File: $outputFileName"

    # 7. 构造合并列表文件 (list.txt)
    # 使用完整的文件名 (包括引号) 来确保文件名中的特殊字符被正确处理
    $videoFileNames | ForEach-Object { 
        "file '$_'" 
    } | Out-File -Encoding UTF8NoBOM -FilePath list.txt

    # 8. 构造并执行合并命令
    # 注意：-c copy 执行的是无损合并，速度极快
    $command = "$ffmpegPath -f concat -safe 0 -i list.txt -c copy '$outputFileName'"

    Write-Host "Executing: $command"
    Invoke-Expression $command

    # 清理 list.txt 文件
    Remove-Item list.txt
}

Write-Host "--- All merging tasks completed. ---"