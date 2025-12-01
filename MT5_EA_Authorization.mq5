//+------------------------------------------------------------------+
//|                                        MT5_EA_Authorization.mq5 |
//|                                    MT5 EA授权验证示例代码        |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "MT5 EA Authorization System"
#property link      "https://mt5-auth-system5-202854-6-1386563557.sh.run.tcloudbase.com"
#property version   "1.00"
#property strict

//--- 输入参数
input string AuthServerURL = "https://mt5-auth-system5-202854-6-1386563557.sh.run.tcloudbase.com/api/verify";  // 授权服务器地址
input int    OfflineHours = 24;                                      // 离线可运行小时数

//--- 全局变量
datetime g_lastVerifyTime = 0;      // 上次验证时间
bool     g_isAuthorized = false;    // 授权状态
string   g_mt5Account = "";         // MT5账号

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- 获取MT5账号
   g_mt5Account = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
   
   Print("========================================");
   Print("MT5 EA授权系统");
   Print("MT5账号: ", g_mt5Account);
   Print("========================================");
   
   //--- 尝试在线验证授权
   if(VerifyAuthorizationOnline())
   {
      g_isAuthorized = true;
      g_lastVerifyTime = TimeCurrent();
      Print("✓ 授权验证成功 - 在线验证");
      return(INIT_SUCCEEDED);
   }
   
   //--- 如果在线验证失败，检查离线缓存
   if(CheckOfflineAuthorization())
   {
      g_isAuthorized = true;
      int remainingHours = GetOfflineRemainingHours();
      Print("✓ 授权验证成功 - 离线模式");
      Print("离线剩余时间: ", remainingHours, " 小时");
      
      if(remainingHours < 6)
      {
         Alert("警告：离线授权即将到期，剩余 ", remainingHours, " 小时");
      }
      
      return(INIT_SUCCEEDED);
   }
   
   //--- 授权验证失败
   Print("✗ 授权验证失败");
   Alert("授权验证失败！\n此MT5账号未授权或授权已过期。\nEA将停止运行。\n\n请联系管理员进行授权。");
   
   return(INIT_FAILED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("EA已停止，原因代码: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- 检查授权状态
   if(!g_isAuthorized)
   {
      Print("未授权，停止运行");
      ExpertRemove();
      return;
   }
   
   //--- 这里添加你的EA交易逻辑
   // ...
}

//+------------------------------------------------------------------+
//| 在线验证授权                                                      |
//+------------------------------------------------------------------+
bool VerifyAuthorizationOnline()
{
   string url = AuthServerURL + "?account=" + g_mt5Account;
   string headers = "Content-Type: application/json\r\n";
   
   char post[];
   char result[];
   string result_string;
   int timeout = 5000; // 5秒超时
   
   //--- 重置错误
   ResetLastError();
   
   //--- 发送HTTP请求
   int res = WebRequest("GET", url, headers, timeout, post, result, headers);
   
   //--- 检查返回码
   if(res == -1)
   {
      int error = GetLastError();
      Print("WebRequest错误: ", error);
      
      if(error == 4060)
      {
         Print("错误：URL未被允许访问");
         Print("请在MT5中添加此URL到允许列表：");
         Print("工具 -> 选项 -> EA交易 -> 允许WebRequest访问以下URL:");
         Print(AuthServerURL);
         Alert("请在MT5中允许WebRequest访问授权服务器！\n\n",
               "操作步骤：\n",
               "1. 工具 -> 选项 -> EA交易\n",
               "2. 勾选 '允许WebRequest访问以下URL'\n",
               "3. 添加URL: ", AuthServerURL, "\n",
               "4. 重启EA");
      }
      
      return false;
   }
   
   if(res != 200)
   {
      Print("HTTP请求失败，状态码: ", res);
      return false;
   }
   
   //--- 解析响应
   result_string = CharArrayToString(result);
   Print("服务器响应: ", result_string);
   
   //--- 解析JSON（简单解析）
   if(StringFind(result_string, "\"authorized\":true") >= 0 || 
      StringFind(result_string, "\"authorized\": true") >= 0)
   {
      //--- 授权成功，保存验证时间
      SaveVerificationTime();
      
      //--- 提取剩余天数信息
      int pos = StringFind(result_string, "\"remaining_days\":");
      if(pos >= 0)
      {
         string remaining = StringSubstr(result_string, pos + 17, 10);
         Print("授权剩余天数: ", remaining);
      }
      
      return true;
   }
   
   //--- 提取错误信息
   int msg_pos = StringFind(result_string, "\"message\":\"");
   if(msg_pos >= 0)
   {
      int msg_start = msg_pos + 11;
      int msg_end = StringFind(result_string, "\"", msg_start);
      string message = StringSubstr(result_string, msg_start, msg_end - msg_start);
      Print("授权失败原因: ", message);
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| 检查离线授权                                                      |
//+------------------------------------------------------------------+
bool CheckOfflineAuthorization()
{
   //--- 加载上次验证时间
   g_lastVerifyTime = (datetime)GlobalVariableGet("LastAuthVerifyTime");
   
   if(g_lastVerifyTime == 0)
   {
      return false;
   }
   
   //--- 计算经过的小时数
   int hoursPassed = (int)((TimeCurrent() - g_lastVerifyTime) / 3600);
   
   //--- 检查是否在允许的离线时间内
   if(hoursPassed < OfflineHours)
   {
      return true;
   }
   
   Print("离线授权已过期，已离线 ", hoursPassed, " 小时");
   return false;
}

//+------------------------------------------------------------------+
//| 获取离线剩余小时数                                                |
//+------------------------------------------------------------------+
int GetOfflineRemainingHours()
{
   if(g_lastVerifyTime == 0)
   {
      return 0;
   }
   
   int hoursPassed = (int)((TimeCurrent() - g_lastVerifyTime) / 3600);
   int remaining = OfflineHours - hoursPassed;
   
   return remaining > 0 ? remaining : 0;
}

//+------------------------------------------------------------------+
//| 保存验证时间                                                      |
//+------------------------------------------------------------------+
void SaveVerificationTime()
{
   g_lastVerifyTime = TimeCurrent();
   GlobalVariableSet("LastAuthVerifyTime", (double)g_lastVerifyTime);
   Print("验证时间已保存: ", TimeToString(g_lastVerifyTime));
}

//+------------------------------------------------------------------+
//| 定时器函数（可选，用于定期检查授权）                              |
//+------------------------------------------------------------------+
void OnTimer()
{
   //--- 可以在这里添加定期验证逻辑
   //--- 例如：每小时尝试在线验证一次
}
//+------------------------------------------------------------------+

