package main

import (
	"fmt"
	"strings"

	"github.com/tw93/mole/internal/i18n"
)

func statusDiagnosisLine(m MetricsSnapshot) string {
	for _, disk := range m.Disks {
		if disk.SmartStatus == smartStatusFailing {
			return i18n.T("SMART failing, back up now", "SMART 故障，请立即备份")
		}
	}
	if m.CPU.Usage > cpuHighThreshold {
		if processSnapshotFresh(m.ProcessStale) {
			if proc, ok := leadingCPUProcess(m.TopProcesses, 50); ok {
				if i18n.Chinese() {
					return fmt.Sprintf("%s CPU 占用高", shorten(proc.Name, 18))
				}
				return fmt.Sprintf("%s high CPU", shorten(proc.Name, 18))
			}
		}
		return i18n.T("CPU load high", "CPU 负载偏高")
	}
	if m.Memory.Pressure == "warn" || m.Memory.Pressure == "critical" || m.Memory.UsedPercent > memHighThreshold {
		if processSnapshotFresh(m.ProcessStale) {
			if proc, ok := leadingMemoryProcess(m.TopProcesses); ok && proc.Memory > 0 {
				if i18n.Chinese() {
					return fmt.Sprintf("%s 内存压力高", shorten(proc.Name, 18))
				}
				return fmt.Sprintf("%s memory pressure", shorten(proc.Name, 18))
			}
		}
		return i18n.T("Memory pressure high", "内存压力偏高")
	}
	if disk, ok := rootDisk(m.Disks); ok && diskIsCritical(disk) {
		free := uint64(0)
		if disk.Total > disk.Used {
			free = disk.Total - disk.Used
		}
		if i18n.Chinese() {
			return fmt.Sprintf("磁盘空间不足，可用 %s", humanBytesShort(free))
		}
		return fmt.Sprintf("Disk low, %s free", humanBytesShort(free))
	}
	for _, battery := range m.Batteries {
		if battery.Capacity > 0 && battery.Capacity < batteryCapWarn {
			return i18n.T("Battery health low", "电池健康度偏低")
		}
		if battery.CycleCount > batteryCycleWarn {
			return i18n.T("Battery cycles high", "电池循环次数偏高")
		}
	}
	if m.Thermal.CPUTemp > thermalNormalThreshold {
		return i18n.T("CPU temperature high", "CPU 温度偏高")
	}
	if totalIO := m.DiskIO.ReadRate + m.DiskIO.WriteRate; totalIO > ioHighThreshold {
		return i18n.T("Disk I/O busy", "磁盘 I/O 繁忙")
	}
	if strings.Contains(m.HealthScoreMsg, ":") {
		return m.HealthScoreMsg
	}
	return i18n.T("All clear", "状态良好")
}

func leadingCPUProcess(procs []ProcessInfo, threshold float64) (ProcessInfo, bool) {
	var best ProcessInfo
	for i, proc := range procs {
		if i == 0 || proc.CPU > best.CPU {
			best = proc
		}
	}
	if best.CPU < threshold {
		return ProcessInfo{}, false
	}
	return best, true
}

func leadingMemoryProcess(procs []ProcessInfo) (ProcessInfo, bool) {
	var best ProcessInfo
	for i, proc := range procs {
		if i == 0 || proc.Memory > best.Memory {
			best = proc
		}
	}
	return best, len(procs) > 0
}

func rootDisk(disks []DiskStatus) (DiskStatus, bool) {
	for _, disk := range disks {
		if disk.Mount == "/" {
			return disk, true
		}
	}
	if len(disks) == 0 {
		return DiskStatus{}, false
	}
	return disks[0], true
}
