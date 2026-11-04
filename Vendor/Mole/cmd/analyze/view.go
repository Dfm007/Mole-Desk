//go:build darwin

package main

import (
	"fmt"
	"path/filepath"
	"strconv"
	"strings"
	"sync/atomic"
	"unicode"

	"github.com/tw93/mole/internal/i18n"
)

// View renders the TUI.
func (m model) View() string {
	var b strings.Builder
	fmt.Fprintln(&b)

	// A warm cache already loaded for the current path keeps rendering while the
	// background refresh runs, instead of blanking to a scan-only screen. Fresh
	// scans (no cached entries yet) still fall back to the scan-only view.
	showingCachedView := m.scanning && !m.inOverviewMode() && m.viewNeedsRefresh && len(m.entries) > 0
	showingLiveScanView := m.scanning && !m.inOverviewMode() && len(m.entries) > 0 &&
		(m.liveScanEvents != nil || len(m.liveScanningPaths) > 0)

	if m.inOverviewMode() {
		freeLabel := ""
		if m.diskFree > 0 {
			freeLabel = fmt.Sprintf("  %s(%s %s)%s", colorGray, humanizeBytes(m.diskFree), i18n.T("free", "可用"), colorReset)
		}
		fmt.Fprintf(&b, "%s%s%s%s\n", colorPurpleBold, i18n.T("Analyze Disk", "磁盘分析"), colorReset, freeLabel)
		if m.localSnapshotCount > 0 {
			freshnessLabel := ""
			if !m.localSnapshotFresh {
				freshnessLabel = " · " + i18n.T("last successful check", "上次检查成功")
			}
			if i18n.Chinese() {
				fmt.Fprintf(&b, "%s%d 个时间机器本地快照 · 快照占用空间未列在下方%s%s\n",
					colorGray, m.localSnapshotCount, freshnessLabel, colorReset)
			} else {
				snapshotLabel := "snapshot"
				if m.localSnapshotCount != 1 {
					snapshotLabel = "snapshots"
				}
				fmt.Fprintf(&b, "%s%d Time Machine local %s · snapshot-only space is not listed below%s%s\n",
					colorGray, m.localSnapshotCount, snapshotLabel, freshnessLabel, colorReset)
			}
		}
		if m.overviewScanning {
			if allOverviewEntriesPending(m.entries) {
				fmt.Fprintf(&b, "%s%s:%s  ", colorGray, i18n.T("Select a location to explore", "选择要分析的位置"), colorReset)
				fmt.Fprintf(&b, "%s%s%s%s %s...\n\n",
					colorCyan, colorBold, spinnerFrames[m.spinner], colorReset, i18n.T("Analyzing disk usage", "正在分析磁盘占用"))
			} else {
				m.writeOverviewStatus(&b)
			}
		} else {
			if hasPendingOverviewEntries(m.entries) {
				m.writeOverviewStatus(&b)
			} else {
				fmt.Fprintf(&b, "%s%s:%s\n\n", colorGray, i18n.T("Select a location to explore", "选择要分析的位置"), colorReset)
			}
		}
	} else {
		fmt.Fprintf(&b, "%s%s%s  %s%s%s", colorPurpleBold, i18n.T("Analyze Disk", "磁盘分析"), colorReset, colorGray, displayPath(m.path), colorReset)
		if !m.scanning || m.totalSize > 0 {
			fmt.Fprintf(&b, "  |  %s: %s", i18n.T("Total", "总计"), measuredSizeLabel(m.totalSize, m.scanState))
		}
		fmt.Fprintf(&b, "\n\n")
	}

	if m.deleting {
		count := int64(0)
		if m.deleteCount != nil {
			count = atomic.LoadInt64(m.deleteCount)
		}

		// The counter is path-level and only advances once a move completes, so a
		// single large directory sits at zero for the whole operation. Printing
		// "0 items removed" there reads as a stalled delete; say what is happening
		// instead, and show the tally only once it means something.
		if count > 0 {
			if i18n.Chinese() {
				fmt.Fprintf(&b, "%s%s%s%s 正在移入废纸篓: %s%s 项%s 已移动，请稍候...\n",
					colorCyan, colorBold, spinnerFrames[m.spinner], colorReset,
					colorYellow, formatNumber(count), colorReset)
			} else {
				fmt.Fprintf(&b, "%s%s%s%s Moving to Trash: %s%s items%s moved, please wait...\n",
					colorCyan, colorBold, spinnerFrames[m.spinner], colorReset,
					colorYellow, formatNumber(count), colorReset)
			}
		} else {
			fmt.Fprintf(&b, "%s%s%s%s %s...\n",
				colorCyan, colorBold,
				spinnerFrames[m.spinner],
				colorReset,
				i18n.T("Moving to Trash, please wait", "正在移入废纸篓，请稍候"))
		}

		return b.String()
	}

	if m.scanning {
		filesScanned, dirsScanned, bytesScanned := m.getScanProgress()

		progressPrefix := ""
		if m.lastTotalFiles > 0 {
			percent := float64(filesScanned) / float64(m.lastTotalFiles) * 100
			// Cap at 100% generally
			if percent > 100 {
				percent = 100
			}
			// While strictly scanning, cap at 99% to avoid "100% but still working" confusion
			if m.scanning && percent >= 100 {
				percent = 99
			}
			progressPrefix = fmt.Sprintf(" %s%.0f%%%s", colorCyan, percent, colorReset)
		}

		statusLine := fmt.Sprintf("%s%s%s%s %s%s: %s%s %s%s, %s%s %s%s, %s%s%s",
			colorCyan, colorBold,
			spinnerFrames[m.spinner],
			colorReset,
			i18n.T("Scanning", "正在扫描"),
			progressPrefix,
			colorYellow, formatNumber(filesScanned), i18n.T("files", "个文件"), colorReset,
			colorYellow, formatNumber(dirsScanned), i18n.T("dirs", "个目录"), colorReset,
			colorGreen, humanizeBytes(bytesScanned), colorReset)

		currentPath := ""
		if m.currentPath != nil {
			currentPath, _ = m.currentPath.Load().(string)
		}

		if currentPath == "" {
			fmt.Fprintf(&b, "%s\n", statusLine)
		} else {
			// Keep the path on the status line whenever the terminal is wide
			// enough to show a useful piece of it, instead of always spending a
			// second row on it. The old code also truncated to a fixed 50
			// columns, which cut paths short on wide terminals and could still
			// overflow narrow ones.
			shortPath := displayPath(currentPath)
			const pathSeparator = "  "
			remaining := m.width - displayWidth(statusLine) - len(pathSeparator)
			if remaining >= scanPathInlineMinWidth {
				fmt.Fprintf(&b, "%s%s%s%s%s\n", statusLine, pathSeparator,
					colorGray, truncateMiddle(shortPath, remaining), colorReset)
			} else {
				pathWidth := max(m.width, scanPathInlineMinWidth)
				fmt.Fprintf(&b, "%s\n%s%s%s\n", statusLine,
					colorGray, truncateMiddle(shortPath, pathWidth), colorReset)
			}
		}

		if !showingCachedView && !showingLiveScanView {
			return b.String()
		}
		if showingCachedView {
			fmt.Fprintf(&b, "%s%s%s\n\n", colorGray, i18n.T("Showing cached results while refreshing...", "正在显示缓存结果并刷新..."), colorReset)
		} else {
			fmt.Fprintln(&b)
		}
	}

	if m.showLargeFiles {
		if m.largeFiltering || m.largeFilter != "" {
			cursor := ""
			if m.largeFiltering {
				cursor = "▌"
			}
			fmt.Fprintf(&b, "  %sFilter:%s %s%s  %s(%d matches)%s\n\n",
				colorCyan, colorReset, m.largeFilter, cursor,
				colorGray, len(m.largeFiles), colorReset)
		}
		if len(m.largeFiles) == 0 {
			if m.largeFilter != "" {
				fmt.Fprintf(&b, "  No matches for %q\n", m.largeFilter)
			} else {
				fmt.Fprintln(&b, "  No large files found")
			}
		} else {
			viewport := calculateViewport(m.height, true)
			start := max(m.largeOffset, 0)
			end := min(start+viewport, len(m.largeFiles))
			maxLargeSize := maxLargeFileSize(m.largeFiles)
			nameWidth := calculateNameWidth(m.width)
			for idx := start; idx < end; idx++ {
				file := m.largeFiles[idx]
				shortPath := displayPath(file.Path)
				shortPath = truncateMiddle(shortPath, nameWidth)
				paddedPath := padName(shortPath, nameWidth)
				entryPrefix := "   "
				nameColor := ""
				sizeColor := colorGray
				numColor := ""

				isMultiSelected := m.largeMultiSelected != nil && m.largeMultiSelected[file.Path]
				selectIcon := "○"
				if isMultiSelected {
					selectIcon = fmt.Sprintf("%s●%s", colorGreen, colorReset)
					nameColor = colorGreen
				}

				if idx == m.largeSelected {
					entryPrefix = fmt.Sprintf(" %s%s▶%s ", colorCyan, colorBold, colorReset)
					if !isMultiSelected {
						nameColor = colorCyan
					}
					sizeColor = colorCyan
					numColor = colorCyan
				}
				size := humanizeBytes(file.Size)
				bar := coloredProgressBar(file.Size, maxLargeSize, 0)
				fmt.Fprintf(&b, "%s%s %s%2d.%s %s  |  📄 %s%s%s  %s%10s%s\n",
					entryPrefix, selectIcon, numColor, idx+1, colorReset, bar, nameColor, paddedPath, colorReset, sizeColor, size, colorReset)
			}
		}
	} else {
		if !m.inOverviewMode() && (m.entryFiltering || m.entryFilter != "") {
			cursor := ""
			if m.entryFiltering {
				cursor = "▌"
			}
			fmt.Fprintf(&b, "  %sFilter:%s %s%s  %s(%d matches)%s\n\n",
				colorCyan, colorReset, m.entryFilter, cursor,
				colorGray, len(m.entries), colorReset)
		}
		if len(m.entries) == 0 {
			if !m.inOverviewMode() && m.entryFilter != "" {
				fmt.Fprintf(&b, "  No matches for %q\n", m.entryFilter)
			} else {
				fmt.Fprintln(&b, "  Empty directory")
			}
		} else {
			if m.inOverviewMode() {
				maxSize := maxDirEntrySize(m.entries)
				totalSize := m.totalSize
				// Overview labels are short; fixed width keeps layout stable.
				nameWidth := 22
				displayNum := 0
				for idx, entry := range m.entries {
					sizeVal := entry.Size
					// Hide entries that have been scanned and are empty (standard dirs
					// are never 0 bytes; only insight dirs in unused tool paths are).
					if sizeVal == 0 && entry.State == scanComplete {
						continue
					}
					barValue := max(sizeVal, 0)
					var percent float64
					if totalSize > 0 && sizeVal >= 0 {
						percent = float64(sizeVal) / float64(totalSize) * 100
					} else {
						percent = 0
					}
					percentStr := formatPercent(percent, totalSize > 0 && sizeVal >= 0 && entry.State == scanComplete && m.scanState == scanComplete)
					bar := coloredProgressBar(barValue, maxSize, percent)
					// Pending rows reuse the list view's scanning idiom: the
					// animated spinner keeps the row visibly alive, and the
					// string is exactly 10 display columns, flush with the
					// right-aligned sizes (a static placeholder read as stuck).
					sizeText := fmt.Sprintf("%s scanning", spinnerFrames[m.spinner])
					sizeColor := colorCyan
					if sizeVal >= 0 {
						sizeText = sizeColumn(measuredSizeLabel(sizeVal, entry.State))
						sizeColor = colorGray
						if totalSize > 0 {
							sizeColor = sizeColorForPercent(percent)
						}
					}
					entryPrefix := "   "
					name := trimNameWithWidth(entry.Name, nameWidth)
					paddedName := padName(name, nameWidth)
					nameSegment := paddedName
					numColor := ""
					percentColor := ""
					if idx == m.selected {
						entryPrefix = fmt.Sprintf(" %s%s▶%s ", colorCyan, colorBold, colorReset)
						nameSegment = fmt.Sprintf("%s%s%s", colorCyan, paddedName, colorReset)
						numColor = colorCyan
						percentColor = colorCyan
						sizeColor = colorCyan
					}
					displayNum++
					displayIndex := displayNum

					// Keep the overview text-only. Emoji width and baselines vary
					// across terminals, while every row has the same navigation.
					hintLabel := ""
					if unusedTime := formatUnusedTime(entry.LastAccess); unusedTime != "" {
						hintLabel = fmt.Sprintf("%s%s%s", colorGray, unusedTime, colorReset)
					}

					if hintLabel == "" {
						fmt.Fprintf(&b, "%s%s%2d.%s %s %s%s%s  |  %s %s%10s%s\n",
							entryPrefix, numColor, displayIndex, colorReset, bar, percentColor, percentStr, colorReset,
							nameSegment, sizeColor, sizeText, colorReset)
					} else {
						fmt.Fprintf(&b, "%s%s%2d.%s %s %s%s%s  |  %s %s%10s%s  %s\n",
							entryPrefix, numColor, displayIndex, colorReset, bar, percentColor, percentStr, colorReset,
							nameSegment, sizeColor, sizeText, colorReset, hintLabel)
					}
				}
			} else {
				maxSize := maxDirEntrySize(m.entries)

				viewport := calculateViewport(m.height, false)
				indexWidth := max(2, len(strconv.Itoa(len(m.entries))))
				nameWidth := calculateNameWidth(m.width) - (indexWidth - 2)
				start := max(m.offset, 0)
				end := min(start+viewport, len(m.entries))

				for idx := start; idx < end; idx++ {
					entry := m.entries[idx]
					icon := "📄"
					if entry.IsDir {
						icon = "📁"
					}
					name := trimNameWithWidth(entry.Name, nameWidth)
					paddedName := padName(name, nameWidth)

					sizeValue := max(entry.Size, 0)
					percent := 0.0
					if m.totalSize > 0 && entry.Size >= 0 {
						percent = float64(entry.Size) / float64(m.totalSize) * 100
					}
					percentStr := formatPercent(percent, entry.Size >= 0 && m.totalSize > 0 && entry.State == scanComplete && m.scanState == scanComplete)

					bar := coloredProgressBar(sizeValue, maxSize, percent)

					sizeColor := sizeColorForPercent(percent)
					size := sizeColumn(measuredSizeLabel(entry.Size, entry.State))
					if entry.Size < 0 {
						size = fmt.Sprintf("%s %s", spinnerFrames[m.spinner], i18n.T("scanning", "扫描中"))
						sizeColor = colorCyan
					}

					isMultiSelected := m.multiSelected != nil && m.multiSelected[entry.Path]
					selectIcon := "○"
					nameColor := ""
					if isMultiSelected {
						selectIcon = fmt.Sprintf("%s●%s", colorGreen, colorReset)
						nameColor = colorGreen
					}

					entryPrefix := "   "
					nameSegment := fmt.Sprintf("%s %s", icon, paddedName)
					if nameColor != "" {
						nameSegment = fmt.Sprintf("%s%s %s%s", nameColor, icon, paddedName, colorReset)
					}
					numColor := ""
					percentColor := ""
					if idx == m.selected {
						entryPrefix = fmt.Sprintf(" %s%s▶%s ", colorCyan, colorBold, colorReset)
						if !isMultiSelected {
							nameSegment = fmt.Sprintf("%s%s %s%s", colorCyan, icon, paddedName, colorReset)
						}
						numColor = colorCyan
						percentColor = colorCyan
						sizeColor = colorCyan
					}

					displayIndex := idx + 1

					hintLabel := entryHintLabel(entry)
					activityMarker := "|"
					if entry.IsDir && m.liveScanningPaths != nil && m.liveScanningPaths[entry.Path] {
						activityMarker = fmt.Sprintf("%s%s%s%s", colorCyan, colorBold, spinnerFrames[m.spinner], colorReset)
					}

					if hintLabel == "" {
						fmt.Fprintf(&b, "%s%s %s%*d.%s %s %s%s%s  %s  %s %s%10s%s\n",
							entryPrefix, selectIcon, numColor, indexWidth, displayIndex, colorReset, bar, percentColor, percentStr, colorReset,
							activityMarker, nameSegment, sizeColor, size, colorReset)
					} else {
						fmt.Fprintf(&b, "%s%s %s%*d.%s %s %s%s%s  %s  %s %s%10s%s  %s\n",
							entryPrefix, selectIcon, numColor, indexWidth, displayIndex, colorReset, bar, percentColor, percentStr, colorReset,
							activityMarker, nameSegment, sizeColor, size, colorReset, hintLabel)
					}
				}
			}
		}
	}

	fmt.Fprintln(&b)
	if m.inOverviewMode() {
		if len(m.history) > 0 {
			fmt.Fprintf(&b, "%s↑↓←→ | %s | R %s | O %s | P %s | F %s | Esc %s | Q/Ctrl+C %s%s\n", colorGray,
				i18n.T("Enter", "回车"), i18n.T("Refresh", "刷新"), i18n.T("Open", "打开"), i18n.T("Preview", "预览"), i18n.T("File", "文件"), i18n.T("Back", "返回"), i18n.T("Quit", "退出"), colorReset)
		} else {
			fmt.Fprintf(&b, "%s↑↓→ | %s | R %s | O %s | P %s | F %s | Esc/Q %s%s\n", colorGray,
				i18n.T("Enter", "回车"), i18n.T("Refresh", "刷新"), i18n.T("Open", "打开"), i18n.T("Preview", "预览"), i18n.T("File", "文件"), i18n.T("Quit", "退出"), colorReset)
		}
	} else if m.showLargeFiles {
		if m.largeFiltering {
			fmt.Fprintf(&b, "%s%s  |  %s %s  |  Esc %s  |  Ctrl+C %s%s\n", colorGray,
				i18n.T("Type to filter", "输入以筛选"), i18n.T("Enter", "回车"), i18n.T("Apply", "应用"), i18n.T("Clear", "清空"), i18n.T("Quit", "退出"), colorReset)
		} else if m.largeFilter != "" {
			fmt.Fprintf(&b, "%s↑↓← | %s %s | / %s | Esc %s | O %s | P %s | F %s | ⌫ %s | Q %s%s\n", colorGray,
				i18n.T("Space", "空格"), i18n.T("Select", "选择"), i18n.T("Edit", "编辑"), i18n.T("Clear filter", "清除筛选"), i18n.T("Open", "打开"), i18n.T("Preview", "预览"), i18n.T("File", "文件"), i18n.T("Del", "删除"), i18n.T("Quit", "退出"), colorReset)
		} else {
			selectCount := len(m.largeMultiSelected)
			if selectCount > 0 {
				fmt.Fprintf(&b, "%s↑↓← | %s %s | / %s | R %s | O %s | P %s | F %s | ⌫ %s %d | Esc %s | Q/Ctrl+C %s%s\n", colorGray,
					i18n.T("Space", "空格"), i18n.T("Select", "选择"), i18n.T("Filter", "筛选"), i18n.T("Refresh", "刷新"), i18n.T("Open", "打开"), i18n.T("Preview", "预览"), i18n.T("File", "文件"), i18n.T("Del", "删除"), selectCount, i18n.T("Back", "返回"), i18n.T("Quit", "退出"), colorReset)
			} else {
				fmt.Fprintf(&b, "%s↑↓← | %s %s | / %s | R %s | O %s | P %s | F %s | ⌫ %s | Esc %s | Q/Ctrl+C %s%s\n", colorGray,
					i18n.T("Space", "空格"), i18n.T("Select", "选择"), i18n.T("Filter", "筛选"), i18n.T("Refresh", "刷新"), i18n.T("Open", "打开"), i18n.T("Preview", "预览"), i18n.T("File", "文件"), i18n.T("Del", "删除"), i18n.T("Back", "返回"), i18n.T("Quit", "退出"), colorReset)
			}
		}
	} else if m.entryFiltering {
		fmt.Fprintf(&b, "%s%s  |  %s %s  |  Esc %s  |  Ctrl+C %s%s\n", colorGray,
			i18n.T("Type to filter", "输入以筛选"), i18n.T("Enter", "回车"), i18n.T("Apply", "应用"), i18n.T("Clear", "清空"), i18n.T("Quit", "退出"), colorReset)
	} else if m.entryFilter != "" {
		fmt.Fprintf(&b, "%s↑↓←→ | %s | %s %s | / %s | Esc %s | O %s | P %s | F %s | ⌫ %s | Q %s%s\n", colorGray,
			i18n.T("Enter", "回车"), i18n.T("Space", "空格"), i18n.T("Select", "选择"), i18n.T("Edit", "编辑"), i18n.T("Clear filter", "清除筛选"), i18n.T("Open", "打开"), i18n.T("Preview", "预览"), i18n.T("File", "文件"), i18n.T("Del", "删除"), i18n.T("Quit", "退出"), colorReset)
	} else {
		largeFileCount := len(m.largeFiles)
		selectCount := len(m.multiSelected)
		if selectCount > 0 {
			if largeFileCount > 0 {
				fmt.Fprintf(&b, "%s↑↓←→ | %s %s | %s | / %s | R %s | O %s | P %s | F %s | ⌫ %s %d | T Top %d | Esc %s | Q/Ctrl+C %s%s\n", colorGray,
					i18n.T("Space", "空格"), i18n.T("Select", "选择"), i18n.T("Enter", "回车"), i18n.T("Filter", "筛选"), i18n.T("Refresh", "刷新"), i18n.T("Open", "打开"), i18n.T("Preview", "预览"), i18n.T("File", "文件"), i18n.T("Del", "删除"), selectCount, largeFileCount, i18n.T("Back", "返回"), i18n.T("Quit", "退出"), colorReset)
			} else {
				fmt.Fprintf(&b, "%s↑↓←→ | %s %s | %s | / %s | R %s | O %s | P %s | F %s | ⌫ %s %d | Esc %s | Q/Ctrl+C %s%s\n", colorGray,
					i18n.T("Space", "空格"), i18n.T("Select", "选择"), i18n.T("Enter", "回车"), i18n.T("Filter", "筛选"), i18n.T("Refresh", "刷新"), i18n.T("Open", "打开"), i18n.T("Preview", "预览"), i18n.T("File", "文件"), i18n.T("Del", "删除"), selectCount, i18n.T("Back", "返回"), i18n.T("Quit", "退出"), colorReset)
			}
		} else {
			if largeFileCount > 0 {
				fmt.Fprintf(&b, "%s↑↓←→ | %s %s | %s | / %s | R %s | O %s | P %s | F %s | ⌫ %s | T Top %d | Esc %s | Q/Ctrl+C %s%s\n", colorGray,
					i18n.T("Space", "空格"), i18n.T("Select", "选择"), i18n.T("Enter", "回车"), i18n.T("Filter", "筛选"), i18n.T("Refresh", "刷新"), i18n.T("Open", "打开"), i18n.T("Preview", "预览"), i18n.T("File", "文件"), i18n.T("Del", "删除"), largeFileCount, i18n.T("Back", "返回"), i18n.T("Quit", "退出"), colorReset)
			} else {
				fmt.Fprintf(&b, "%s↑↓←→ | %s %s | %s | / %s | R %s | O %s | P %s | F %s | ⌫ %s | Esc %s | Q/Ctrl+C %s%s\n", colorGray,
					i18n.T("Space", "空格"), i18n.T("Select", "选择"), i18n.T("Enter", "回车"), i18n.T("Filter", "筛选"), i18n.T("Refresh", "刷新"), i18n.T("Open", "打开"), i18n.T("Preview", "预览"), i18n.T("File", "文件"), i18n.T("Del", "删除"), i18n.T("Back", "返回"), i18n.T("Quit", "退出"), colorReset)
			}
		}
	}
	if m.deleteConfirm && m.deleteTarget != nil {
		fmt.Fprintln(&b)
		var deleteCount int
		var totalDeleteSize int64
		deleteState := scanComplete
		hasAppBundle := false
		if m.showLargeFiles && len(m.largeMultiSelected) > 0 {
			deleteCount = len(m.largeMultiSelected)
			for path := range m.largeMultiSelected {
				for _, file := range m.largeFiles {
					if file.Path == path {
						totalDeleteSize += file.Size
						break
					}
				}
			}
		} else if !m.showLargeFiles && len(m.multiSelected) > 0 {
			deleteCount = len(m.multiSelected)
			totalDeleteSize, deleteState = m.selectedEntryMeasurement()
			for _, entry := range m.entries {
				if m.multiSelected[entry.Path] && isAppBundleEntry(entry) {
					hasAppBundle = true
					break
				}
			}
		}

		if deleteCount > 1 {
			fmt.Fprintf(&b, "%s%s:%s %d %s, %s  %s%s  |  ESC %s%s\n",
				colorRed, colorReset,
				i18n.T("Move to Trash", "移入废纸篓"), deleteCount, i18n.T("items", "项"),
				measuredSizeLabel(totalDeleteSize, deleteState),
				colorGray, i18n.T("Press Enter to confirm", "按回车确认"), i18n.T("cancel", "取消"), colorReset)
		} else {
			fmt.Fprintf(&b, "%s%s:%s %s, %s  %s%s  |  ESC %s%s\n",
				colorRed, colorReset,
				i18n.T("Move to Trash", "移入废纸篓"),
				m.deleteTarget.Name, measuredSizeLabel(m.deleteTarget.Size, m.deleteTarget.State),
				colorGray, i18n.T("Press Enter to confirm", "按回车确认"), i18n.T("cancel", "取消"), colorReset)
		}
		if deleteCount > 1 && hasAppBundle {
			fmt.Fprintf(&b, "%s%s%s\n",
				i18n.T("Only the app bundle moves to Trash. Use mo uninstall <App> to also remove support files.", "只会将应用本体移入废纸篓。使用 mo uninstall <App> 可同时移除支持文件。"),
				colorYellow, colorReset)
		} else if deleteCount <= 1 && isAppBundleEntry(*m.deleteTarget) {
			if i18n.Chinese() {
				fmt.Fprintf(&b, "%s应用本体：只会将应用移入废纸篓。使用 %s 可同时移除支持文件。%s\n",
					colorYellow, uninstallCommandForApp(m.deleteTarget.Name), colorReset)
			} else {
				fmt.Fprintf(&b, "%sApp bundle: only the bundle moves to Trash. Use %s to also remove its support files.%s\n",
					colorYellow, uninstallCommandForApp(m.deleteTarget.Name), colorReset)
			}
		}
	}
	return b.String()
}

func (m model) writeOverviewStatus(b *strings.Builder) {
	prompt := i18n.T("Select a location to explore:", "选择要分析的位置：")
	status := m.status
	inlineWidth := displayWidth(prompt) + 2 + displayWidth(spinnerFrames[m.spinner]) + 1 + displayWidth(status)
	if m.width > 0 && inlineWidth > m.width {
		fmt.Fprintf(b, "%s%s%s\n", colorGray, prompt, colorReset)
		status = truncateMiddle(status, max(0, m.width-displayWidth(spinnerFrames[m.spinner])-1))
	} else {
		fmt.Fprintf(b, "%s%s%s  ", colorGray, prompt, colorReset)
	}
	fmt.Fprintf(b, "%s%s%s%s %s\n\n", colorCyan, colorBold, spinnerFrames[m.spinner], colorReset, status)
}

// isAppBundleEntry reports whether a scanned entry is a macOS application
// bundle: a directory whose name ends in ".app". Contents are not inspected;
// the hint this powers is informational, so a false positive on a plain
// folder named like a bundle is harmless.
func isAppBundleEntry(entry dirEntry) bool {
	return entry.IsDir && strings.EqualFold(filepath.Ext(entry.Name), ".app")
}

// uninstallCommandForApp renders a shell-safe mo uninstall invocation for an
// app bundle name. Simple names stay unquoted; other printable names use POSIX
// single-quote escaping. Names that look like flags or contain control
// characters fall back to the generic placeholder.
func uninstallCommandForApp(name string) string {
	appName := strings.TrimSuffix(name, filepath.Ext(name))
	if appName == "" {
		appName = name
	}
	if appName == "" || strings.HasPrefix(appName, "-") || strings.IndexFunc(appName, unicode.IsControl) >= 0 {
		return "mo uninstall <App>"
	}
	if isShellSafeUnquotedAppName(appName) {
		return "mo uninstall " + appName
	}
	return "mo uninstall '" + strings.ReplaceAll(appName, "'", `'\''`) + "'"
}

func isShellSafeUnquotedAppName(name string) bool {
	for _, r := range name {
		if r >= 'a' && r <= 'z' ||
			r >= 'A' && r <= 'Z' ||
			r >= '0' && r <= '9' {
			continue
		}
		switch r {
		case '_', '-', '.', '+':
			continue
		default:
			return false
		}
	}
	return name != ""
}

func allOverviewEntriesPending(entries []dirEntry) bool {
	for _, entry := range entries {
		if entry.Size >= 0 {
			return false
		}
	}
	return true
}

func maxLargeFileSize(files []fileEntry) int64 {
	var maxSize int64 = 1
	for _, file := range files {
		if file.Size > maxSize {
			maxSize = file.Size
		}
	}
	return maxSize
}

func maxDirEntrySize(entries []dirEntry) int64 {
	var maxSize int64 = 1
	for _, entry := range entries {
		if entry.Size > maxSize {
			maxSize = entry.Size
		}
	}
	return maxSize
}

func sizeColorForPercent(percent float64) string {
	switch {
	case percent >= 50:
		return colorRed
	case percent >= 20:
		return colorYellow
	case percent >= 5:
		return colorBlue
	default:
		return colorGray
	}
}

func entryHintLabel(entry dirEntry) string {
	if entry.IsDir && isCleanableDir(entry.Path) {
		return fmt.Sprintf("%s🧹%s", colorYellow, colorReset)
	}
	if unusedTime := formatUnusedTime(entry.LastAccess); unusedTime != "" {
		return fmt.Sprintf("%s%s%s", colorGray, unusedTime, colorReset)
	}
	return ""
}

// calculateViewport returns visible rows for the current terminal height.
func calculateViewport(termHeight int, isLargeFiles bool) int {
	if termHeight <= 0 {
		return defaultViewport
	}

	reserved := 6 // Header + footer
	if isLargeFiles {
		reserved = 5
	}

	available := termHeight - reserved

	if available < 1 {
		return 1
	}
	if available > 30 {
		return 30
	}

	return available
}
