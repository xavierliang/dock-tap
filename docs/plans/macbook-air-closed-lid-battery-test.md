# MacBook Air 合盖电池模式测试方案

## 背景

目标是验证 MacBook Air 在“合盖 + 电池模式”下，是否可以继续保持系统唤醒、任务执行和 Wi-Fi 在线。

macOS 默认会在合盖后进入睡眠。普通 `caffeinate` 主要防止空闲睡眠，通常挡不住合盖睡眠；真正需要验证的是 `pmset disablesleep` 是否能在目标机器和当前 macOS 版本上生效。

## 测试目标

- 合盖后后台任务是否继续执行。
- 合盖后 Wi-Fi 是否保持在线。
- 电池模式下耗电和温度是否可接受。
- 测试结束后系统睡眠设置是否能恢复。

## 安全边界

- 只在桌面、通风环境测试，不放入包里或被子上。
- 首轮只测 3 到 5 分钟。
- 电量低于 50% 不做长时间测试。
- 测试结束必须执行恢复命令：

```bash
sudo pmset -a disablesleep 0
```

## 测试准备

创建测试目录：

```bash
mkdir -p ~/Desktop/lid-test
```

记录当前电源设置：

```bash
pmset -g custom > ~/Desktop/lid-test/pmset-before.txt
```

启动 heartbeat 日志：

```bash
while true; do
  echo "$(date '+%F %T') | $(pmset -g batt | tail -1)" >> ~/Desktop/lid-test/heartbeat.log
  sleep 10
done
```

另开一个终端启动 Wi-Fi 日志：

```bash
while true; do
  echo "---- $(date '+%F %T') ----" >> ~/Desktop/lid-test/wifi.log
  pmset -g batt | tail -1 >> ~/Desktop/lid-test/wifi.log
  networksetup -getairportnetwork en0 >> ~/Desktop/lid-test/wifi.log 2>&1
  ping -c 1 -t 2 1.1.1.1 >> ~/Desktop/lid-test/wifi.log 2>&1
  echo "" >> ~/Desktop/lid-test/wifi.log
  sleep 10
done
```

## 测试步骤

### 1. 默认合盖测试

不改任何设置，拔掉电源，合盖 3 分钟。

开盖后检查：

```bash
tail -50 ~/Desktop/lid-test/heartbeat.log
tail -80 ~/Desktop/lid-test/wifi.log
```

预期结果：日志在合盖期间中断，说明系统睡眠，Wi-Fi 也不保持持续在线。

### 2. caffeinate 测试

运行：

```bash
caffeinate -im
```

保持 heartbeat 和 Wi-Fi 日志运行，拔掉电源，合盖 3 分钟。

预期结果：大概率仍然睡眠。这个测试用于确认普通 idle sleep assertion 不足以解决合盖场景。

### 3. disablesleep 测试

开启：

```bash
sudo pmset -a disablesleep 1
```

保持 heartbeat 和 Wi-Fi 日志运行，拔掉电源，合盖 3 到 5 分钟。

开盖后立刻恢复：

```bash
sudo pmset -a disablesleep 0
pmset -g custom > ~/Desktop/lid-test/pmset-after.txt
```

检查日志：

```bash
tail -80 ~/Desktop/lid-test/heartbeat.log
tail -120 ~/Desktop/lid-test/wifi.log
pmset -g log | grep -i "sleep\\|wake\\|clamshell" | tail -80
```

## 成功标准

认为方案有效，需要同时满足：

- `heartbeat.log` 在合盖期间每 10 秒持续写入。
- `wifi.log` 在合盖期间持续写入，并且 `ping 1.1.1.1` 成功。
- `pmset -g log` 在对应时间段没有 `Clamshell Sleep`。
- 开盖后系统状态正常，执行 `sudo pmset -a disablesleep 0` 后可以正常睡眠。

## 后续产品化方案

如果测试有效，再考虑写一个小工具，不建议只做一个简单常驻进程。

最小架构：

- 菜单栏 App：显示开关、剩余时间、电量、温度状态。
- Privileged Helper：执行 `pmset -a disablesleep 1/0`，避免主 App 直接持有管理员权限。
- Watchdog：每 30 到 60 秒检查主 App 是否续期；如果主 App 崩溃或超时，自动恢复 `disablesleep 0`。
- 安全策略：低电量、超时、温度异常、切回电源策略时自动恢复睡眠。
- IOKit assertion：辅助防止普通空闲睡眠，但不把它当成合盖不睡眠的核心能力。

优先级：

1. 先完成 3 到 5 分钟人工测试。
2. 再做 15 分钟电池和 Wi-Fi 稳定性测试。
3. 确认有效后，再写带 watchdog 的菜单栏工具。

## 结论

技术上可以测试 `pmset disablesleep` 路径，但必须把恢复机制放在第一优先级。合盖电池模式持续运行会增加耗电和发热风险，最终工具必须有超时、电量阈值和崩溃恢复。
