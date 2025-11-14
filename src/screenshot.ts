import { showToast, Toast } from "@raycast/api";
import { spawn, exec } from "child_process";
import { promisify } from "util";
import { join, dirname, resolve } from "path";
import { tmpdir } from "os";
import { existsSync, unlinkSync } from "fs";

const execAsync = promisify(exec);

export default async function Command() {
  let screenshotPath = "";
  try {
    // 生成临时文件路径
    const timestamp = Date.now();
    screenshotPath = join(tmpdir(), `raycast-screenshot-${timestamp}.png`);

    // 使用 screencapture 命令截图（-i 表示交互式选择区域）
    // 使用 spawn 而不是 exec，因为用户取消时会返回非零退出码
    // 使用完整路径，因为 Raycast 运行时环境可能不包含 /usr/sbin 在 PATH 中
    await new Promise<void>((resolve, reject) => {
      const screencapture = spawn("/usr/sbin/screencapture", ["-i", screenshotPath], {
        stdio: "ignore",
      });

      screencapture.on("close", (code) => {
        // 检查文件是否存在，而不是检查退出码
        // 因为用户取消时退出码不为0，但这是正常情况
        if (existsSync(screenshotPath)) {
          resolve();
        } else {
          // 文件不存在，可能是用户取消了
          reject(new Error("用户取消了截图操作"));
        }
      });

      screencapture.on("error", (error) => {
        reject(error);
      });
    });

    // 显示悬浮窗口（窗口关闭时会自动清理临时文件）
    await showFloatingWindow(screenshotPath);
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : "未知错误";
    
    // 如果是用户取消，显示不同的提示
    if (errorMessage.includes("取消")) {
      // 用户取消不需要显示错误提示
      return;
    }
    
    await showToast({
      style: Toast.Style.Failure,
      title: "截图失败",
      message: errorMessage,
    });
    
    // 如果出错，清理临时文件
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
  // 使用 sips 命令获取图片尺寸
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
    // 如果获取失败，返回默认值
  }
  
  // 默认尺寸
  return { width: 800, height: 600 };
}

async function findProjectRoot(): Promise<string | null> {
  // 从当前文件位置向上查找，直到找到 package.json 或 build-native.sh
  let currentDir = __dirname;
  const maxDepth = 10;
  let depth = 0;
  
  while (depth < maxDepth) {
    const packageJsonPath = join(currentDir, "package.json");
    const buildScriptPath = join(currentDir, "build-native.sh");
    
    if (existsSync(packageJsonPath) || existsSync(buildScriptPath)) {
      return currentDir;
    }
    
    const parentDir = join(currentDir, "..");
    if (parentDir === currentDir) {
      break; // 到达根目录
    }
    currentDir = parentDir;
    depth++;
  }
  
  return null;
}

async function showFloatingWindow(imagePath: string) {
  // 获取 float-window 可执行文件的路径
  let floatWindowPath: string | null = null;
  
  // 方法1: 查找项目根目录
  const projectRoot = await findProjectRoot();
  if (projectRoot) {
    const pathInRoot = join(projectRoot, "float-window");
    if (existsSync(pathInRoot)) {
      floatWindowPath = pathInRoot;
    }
  }
  
  // 方法2: 如果还没找到，尝试多个可能的路径
  if (!floatWindowPath) {
    const possiblePaths = [
      // 从编译后的 dist 目录向上查找
      join(__dirname, "..", "float-window"),
      // 从当前工作目录查找
      resolve(process.cwd(), "float-window"),
      // 从 __dirname 向上两级查找
      join(__dirname, "..", "..", "float-window"),
      // 使用环境变量（如果 Raycast 提供了）
      process.env.RAYCAST_EXTENSION_PATH ? join(process.env.RAYCAST_EXTENSION_PATH, "float-window") : null,
    ].filter((path): path is string => path !== null);
    
    for (const path of possiblePaths) {
      if (existsSync(path)) {
        floatWindowPath = path;
        break;
      }
    }
  }
  
  // 方法3: 检查是否在系统 PATH 中
  if (!floatWindowPath) {
    try {
      const { stdout } = await execAsync("which float-window");
      if (stdout.trim()) {
        floatWindowPath = stdout.trim();
      }
    } catch (error) {
      // 不在 PATH 中
    }
  }
  
  // 如果还是找不到，尝试自动编译
  if (!floatWindowPath || !existsSync(floatWindowPath)) {
    const buildScriptPath = projectRoot ? join(projectRoot, "build-native.sh") : join(__dirname, "..", "build-native.sh");
    const sourceFile = projectRoot ? join(projectRoot, "FloatWindow.m") : join(__dirname, "..", "FloatWindow.m");
    
    // 如果源文件存在，尝试编译
    if (existsSync(sourceFile) && existsSync(buildScriptPath)) {
      try {
        // 切换到项目根目录执行编译
        const cwd = projectRoot || join(__dirname, "..");
        await execAsync(`bash "${buildScriptPath}"`, { cwd });
        // 重新查找
        if (projectRoot) {
          const pathInRoot = join(projectRoot, "float-window");
          if (existsSync(pathInRoot)) {
            floatWindowPath = pathInRoot;
          }
        }
      } catch (error) {
        // 编译失败，继续查找其他位置
      }
    }
  }
  
  // 检查可执行文件是否存在
  if (!floatWindowPath || !existsSync(floatWindowPath)) {
    await showToast({
      style: Toast.Style.Failure,
      title: "错误",
      message: `找不到 float-window 可执行文件。\n\n项目根目录: ${projectRoot || "未找到"}\n__dirname: ${__dirname}\n\n请运行：./build-native.sh`,
    });
    return;
  }

  // 使用原生应用创建悬浮窗口（支持点击穿透）
  const floatProcess = spawn(floatWindowPath, [imagePath], {
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
          -- 检查 float-window 进程是否还在运行
          set processExists to false
          try
            set processList to (every process whose name is "float-window")
            if (count of processList) > 0 then
              set processExists to true
            end if
          end try
          
          if not processExists then
            -- 进程已退出，清理临时文件
            do shell script "rm -f '${imagePath}'"
            exit repeat
          end if
          
          delay 0.3
        on error
          -- 出错时也清理文件
          try
            do shell script "rm -f '${imagePath}'"
          end try
          exit repeat
        end try
      end repeat
    end tell
  `;

  // 在后台运行监控脚本
  const monitorProcess = spawn("/usr/bin/osascript", ["-e", monitorScript], {
    detached: true,
    stdio: "ignore",
  });
  
  monitorProcess.unref();
  
  // 原生应用支持：
  // - 点击穿透（ignoresMouseEvents = YES）
  // - 窗口始终在最上层（NSFloatingWindowLevel）
  // - 图片 1:1 显示
  // - ESC 键关闭窗口
}

