import { showToast, Toast, closeMainWindow } from "@raycast/api";
import { spawn, exec } from "child_process";
import { promisify } from "util";
import { join } from "path";
import { tmpdir } from "os";
import { existsSync, unlinkSync } from "fs";

const execAsync = promisify(exec);

export default async function Command() {
  let screenshotPath = "";
  try {
    // 立即关闭 Raycast 主窗口
    await closeMainWindow();

    // 生成临时文件路径
    const timestamp = Date.now();
    screenshotPath = join(tmpdir(), `raycast-screenshot-${timestamp}.png`);

    // 使用 screencapture 命令截图（-i 表示交互式选择区域）
    let screenshotRect: { x: number; y: number; width: number; height: number } | null = null;
    let finalRect: { x: number; y: number; width: number; height: number } | null = null;

    await new Promise<void>((resolve, reject) => {
      const screencapture = spawn("/usr/sbin/screencapture", ["-i", screenshotPath], {
        stdio: "ignore",
      });

      screencapture.on("close", (code) => {
        if (existsSync(screenshotPath)) {
          resolve();
        } else {
          reject(new Error("用户取消了截图操作"));
        }
      });

      screencapture.on("error", (error) => {
        reject(error);
      });
    });

    // 获取截图区域信息
    try {
      // 获取鼠标位置作为截图区域的近似位置
      const mousePosition = await getMousePosition();
      if (mousePosition) {
        // 获取图片实际尺寸
        const dimensions = await getImageDimensions(screenshotPath);

        // 使用鼠标位置作为截图区域的中心点
        const width = dimensions.width;
        const height = dimensions.height;
        const x = mousePosition.x - width / 2;
        const y = mousePosition.y - height / 2;
        finalRect = { x, y, width, height };
      }
    } catch (e) {
      console.error("获取截图区域信息失败:", e);
    }

    // 显示悬浮窗口
    await showFloatingWindow(screenshotPath, finalRect);
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : "未知错误";

    if (errorMessage.includes("取消")) {
      return;
    }

    await showToast({
      style: Toast.Style.Failure,
      title: "截图失败",
      message: errorMessage,
    });

    if (screenshotPath && existsSync(screenshotPath)) {
      try {
        unlinkSync(screenshotPath);
      } catch (e) {
        // 忽略清理错误
      }
    }
  }
}

async function getImageDimensions(imagePath: string): Promise<{ width: number; height: number }> {
  try {
    const { stdout } = await execAsync(`/usr/bin/sips -g pixelWidth -g pixelHeight "${imagePath}"`);
    const widthMatch = stdout.match(/pixelWidth: (\d+)/);
    const heightMatch = stdout.match(/pixelHeight: (\d+)/);

    if (widthMatch && heightMatch) {
      return {
        width: parseInt(widthMatch[1], 10),
        height: parseInt(heightMatch[1], 10),
      };
    }
  } catch (error) {
    // 忽略错误
  }
  return { width: 800, height: 600 };
}

async function getBinaryPath(binaryName: string): Promise<string | null> {
  // 优先检查当前目录（dist目录）
  const currentDirBinary = join(__dirname, binaryName);
  if (existsSync(currentDirBinary)) {
    return currentDirBinary;
  }

  // 检查 assets 目录（如果使用了 assets）
  const assetsDirBinary = join(__dirname, "assets", binaryName);
  if (existsSync(assetsDirBinary)) {
    return assetsDirBinary;
  }

  // 检查项目根目录（开发环境）
  const rootDirBinary = join(__dirname, "..", binaryName);
  if (existsSync(rootDirBinary)) {
    return rootDirBinary;
  }

  // 检查系统 PATH
  try {
    const { stdout } = await execAsync(`which ${binaryName}`);
    if (stdout.trim()) {
      return stdout.trim();
    }
  } catch (error) {
    // 忽略
  }

  return null;
}

async function getMousePosition(): Promise<{ x: number; y: number } | null> {
  const binaryPath = await getBinaryPath("get_mouse_position");

  if (!binaryPath) {
    console.error("找不到 get_mouse_position 可执行文件");
    return null;
  }

  try {
    const { stdout } = await execAsync(`"${binaryPath}"`);
    const [x, y] = stdout.trim().split(',').map(Number);
    return { x, y };
  } catch (error) {
    console.error("获取鼠标位置失败:", error);
    return null;
  }
}

async function showFloatingWindow(imagePath: string, screenshotRect: { x: number; y: number; width: number; height: number } | null) {
  const binaryPath = await getBinaryPath("float-window");

  if (!binaryPath) {
    await showToast({
      style: Toast.Style.Failure,
      title: "错误",
      message: "找不到 float-window 可执行文件",
    });
    return;
  }

  const args = [imagePath];
  if (screenshotRect) {
    args.push(
      screenshotRect.x.toString(),
      screenshotRect.y.toString(),
      screenshotRect.width.toString(),
      screenshotRect.height.toString()
    );
  }

  const floatProcess = spawn(binaryPath, args, {
    detached: true,
    stdio: "ignore",
  });

  floatProcess.unref();

  // 等待窗口打开
  await new Promise((resolve) => setTimeout(resolve, 500));

  // 监控进程状态，当进程退出时清理临时文件
  const monitorScript = `
    tell application "System Events"
      repeat
        try
          set processExists to false
          try
            set processList to (every process whose name is "float-window")
            if (count of processList) > 0 then
              set processExists to true
            end if
          end try
          
          if not processExists then
            do shell script "rm -f '${imagePath}'"
            exit repeat
          end if
          
          delay 0.5
        on error
          try
            do shell script "rm -f '${imagePath}'"
          end try
          exit repeat
        end try
      end repeat
    end tell
  `;

  const monitorProcess = spawn("/usr/bin/osascript", ["-e", monitorScript], {
    detached: true,
    stdio: "ignore",
  });

  monitorProcess.unref();
}


