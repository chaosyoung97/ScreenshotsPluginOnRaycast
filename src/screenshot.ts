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
    let screenshotRect: { x: number; y: number; width: number; height: number } | null = null;
    
    // 用于存储截图区域信息
    let finalRect: { x: number; y: number; width: number; height: number } | null = null;
    
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
    
    // 获取截图区域信息
    try {
      // 使用 AppleScript 获取截图区域信息
      const { stdout } = await execAsync(`osascript -e '
        try
          tell application "System Events"
            set frontApp to name of first application process whose frontmost is true
          end tell
          return frontApp
        on error
          return "Unknown"
        end try
      '`);
      
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
      // 获取截图区域信息失败，继续使用默认方式
      console.error("获取截图区域信息失败:", e);
    }

    // 隐藏 Raycast 启动台
    try {
      await execAsync("osascript -e 'tell application \"Raycast\" to activate' && osascript -e 'tell application \"System Events\" to keystroke \"h\" using {command down, option down}'");
    } catch (e) {
      // 忽略隐藏启动台的错误
    }

    // 等待一小段时间确保启动台隐藏
    await new Promise((resolve) => setTimeout(resolve, 100));

    // 显示悬浮窗口（窗口关闭时会自动清理临时文件）
    await showFloatingWindow(screenshotPath, finalRect);
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

async function getMousePosition(): Promise<{ x: number; y: number } | null> {
  // 获取 float-window 可执行文件的路径
  let mousePositionPath: string | null = null;
  
  // 查找项目根目录
  const projectRoot = await findProjectRoot();
  if (projectRoot) {
    const pathInRoot = join(projectRoot, "get_mouse_position");
    if (existsSync(pathInRoot)) {
      mousePositionPath = pathInRoot;
    }
  }
  
  // 如果还没找到，尝试多个可能的路径
  if (!mousePositionPath) {
    const possiblePaths = [
      // 从编译后的 dist 目录向上查找
      join(__dirname, "..", "get_mouse_position"),
      // 从当前工作目录查找
      resolve(process.cwd(), "get_mouse_position"),
      // 从 __dirname 向上两级查找
      join(__dirname, "..", "..", "get_mouse_position"),
      // 使用环境变量（如果 Raycast 提供了）
      process.env.RAYCAST_EXTENSION_PATH ? join(process.env.RAYCAST_EXTENSION_PATH, "get_mouse_position") : null,
    ].filter((path): path is string => path !== null);
    
    for (const path of possiblePaths) {
      if (existsSync(path)) {
        mousePositionPath = path;
        break;
      }
    }
  }
  
  // 检查可执行文件是否存在
  if (!mousePositionPath || !existsSync(mousePositionPath)) {
    // 尝试编译
    const sourceFile = projectRoot ? join(projectRoot, "get_mouse_position.m") : join(__dirname, "..", "get_mouse_position.m");
    
    // 如果源文件存在，尝试编译
    if (existsSync(sourceFile)) {
      try {
        // 切换到项目根目录执行编译
        const cwd = projectRoot || join(__dirname, "..");
        const { stdout, stderr } = await execAsync(`clang -framework Cocoa -o get_mouse_position get_mouse_position.m`, { cwd });
        // 重新查找
        if (projectRoot) {
          const pathInRoot = join(projectRoot, "get_mouse_position");
          if (existsSync(pathInRoot)) {
            mousePositionPath = pathInRoot;
          }
        }
      } catch (error) {
        // 编译失败
        console.error("编译get_mouse_position失败:", error);
        return null;
      }
    }
  }
  
  // 检查可执行文件是否存在
  if (!mousePositionPath || !existsSync(mousePositionPath)) {
    console.error("找不到 get_mouse_position 可执行文件");
    return null;
  }
  
  try {
    const { stdout } = await execAsync(mousePositionPath);
    const [x, y] = stdout.trim().split(',').map(Number);
    return { x, y };
  } catch (error) {
    console.error("获取鼠标位置失败:", error);
    return null;
  }
}

async function showFloatingWindow(imagePath: string, screenshotRect: { x: number; y: number; width: number; height: number } | null) {
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
      message: `找不到 float-window 可执行文件。

项目根目录: ${projectRoot || "未找到"}
__dirname: ${__dirname}

请运行：./build-native.sh`,
    });
    return;
  }

  // 使用原生应用创建悬浮窗口（支持点击穿透）
  // 将截图区域信息传递给悬浮窗口应用
  const args = [imagePath];
  if (screenshotRect) {
    args.push(
      screenshotRect.x.toString(), 
      screenshotRect.y.toString(),
      screenshotRect.width.toString(),
      screenshotRect.height.toString()
    );
  }
  
  const floatProcess = spawn(floatWindowPath, args, {
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

