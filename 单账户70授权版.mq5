//+------------------------------------------------------------------+
//|                          GoldHedgeEA Single Account              |
//|         单账户双向对冲版本：在同一账户内同时持有多/空并协同       |
//|         变体：手数>=0.32 时盈利目标=手数*2000                    |
//|         授权版：集成网站授权验证                                  |
//+------------------------------------------------------------------+
#property copyright "Gold Hedge System"
#property version   "3.0"
#property description "单账户多空协同对冲版本，固定阶梯+大手盈利*2000变体 - 授权版"

#include <Trade\Trade.mqh>

//=== 输入参数（仅授权接口） ===
input string   AuthServerURL        = "https://jsqy.online/api/verify";

//=== 固定配置（已隐藏） ===
const double   InitialLot         = 0.01;          // 初始手数
const double   MaxLot             = 10.0;          // 最大手数限制
const double   ProfitTarget1      = 2.0;           // 第一次盈利目标(美元)
const double   ProfitTarget2      = 6.0;           // 第二次盈利目标(美元)
const int      MaxSlippage        = 20;            // 最大滑点(点)
const long     MagicNumberLong    = 20240520;      // 多单魔术码
const long     MagicNumberShort   = 20240521;      // 空单魔术码
const int      OrderExecutionMaxRetries = 3;       // 下单最大重试

// 授权隐藏配置（可在源码中修改，终端输入参数中不可见）
const string   AUTH_TOKEN               = "";       // 可选：额外校验令牌
const int      AUTH_RECHECK_INTERVAL    = 0;        // 0=仅启动时校验，不再定期重检
const bool     BLOCK_WHEN_UNAUTHORIZED  = true;     // 未授权时是否阻止交易

//=== 全局状态 ===
enum ENUM_SIDE {SIDE_LONG=0, SIDE_SHORT=1};

struct SideState
{
   int    tradeCount;
   double currentLot;
   double firstTradePrice;
   double lastTradePrice;
   double secondTradePrice;
   int    hedgeCount;
   double totalHedgeVolume;
   double firstHedgePrice;
   double lastHedgePrice;
   double secondLastHedgePrice;
};

SideState g_long = {0};
SideState g_short = {0};
bool isProcessing = false;
datetime lastUpdateLog = 0;

// 授权相关全局变量
bool     g_isAuthorized = false;
datetime g_lastAuthCheck = 0;
int      g_authFailedCount = 0;
string   g_lastAuthMessage = "";

//=== 辅助函数声明 ===
double NormalizeLot(double volume);
double GetFixedProfitTargetByLot(double lot);
double GetFixedReentryLot(double lastLot);
double CalculateRequiredMargin(double volume);

int    GetPositionCount(bool isLongSide);
double CalculateTotalVolume(bool isLongSide);
double CalculateCurrentProfit(bool isLongSide);
bool   ExecuteTrade(double volume, string comment, bool isLongSide);
bool   ClosePositions(bool isLongSide);
bool   ExecuteInitialTrades();

double CalculateNextHedgeLot(SideState &state);
bool   ExecuteHedgeTrade(bool isLongSide);
bool   HandleProfitSide(bool profitIsLong);

void   CheckTradingConditions();
void   CheckResetConditions();
void   ExecuteGlobalReset();
void   ResetAccountState();

// 授权相关函数
string TrimString(const string value);
string ToLowerString(const string value);
bool   VerifyAuthorization(const bool force = false);
bool   ParseAuthorizationResponse(const string &body);
void   HandleUnauthorizedState(const string &reason);

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== 单账户双向对冲EA启动（*2000变体 - 授权版） ===");
   
   if(!VerifyAuthorization(true))
   {
      Print("❌ 授权校验失败，原因: ", g_lastAuthMessage);
      MessageBox("授权校验失败，请检查网站授权或网络连接。\n错误详情: " + g_lastAuthMessage,
                 "授权失败", MB_ICONSTOP);
      return INIT_FAILED;
   }

   if(InitialLot <= 0 || InitialLot > MaxLot)
   {
      Print("❌ 初始手数无效: ", InitialLot);
      return INIT_PARAMETERS_INCORRECT;
   }

   if(!ExecuteInitialTrades())
   {
      Print("❌ 初始多空建仓失败");
      return INIT_FAILED;
   }

   EventSetTimer(1);
   Print("✅ 初始化完成");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   Print("EA停止，原因: ", reason);
}

//+------------------------------------------------------------------+
//| OnTimer                                                          |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(AUTH_RECHECK_INTERVAL > 0 && (TimeCurrent() - g_lastAuthCheck) >= AUTH_RECHECK_INTERVAL)
      VerifyAuthorization(true);
   
   if(!g_isAuthorized)
      return;

   if(isProcessing)
      return;

   CheckTradingConditions();
   CheckResetConditions();

   datetime now = TimeCurrent();
   if(now - lastUpdateLog >= 5)
   {
      PrintFormat("📊 状态 多仓:手数=%.2f 仓位数=%d | 空仓:手数=%.2f 仓位数=%d",
                  CalculateTotalVolume(true), GetPositionCount(true),
                  CalculateTotalVolume(false), GetPositionCount(false));
      lastUpdateLog = now;
   }
}

//+------------------------------------------------------------------+
//| 字符串工具函数                                                    |
//+------------------------------------------------------------------+
string TrimString(const string value)
{
   string temp = value;
   StringTrimLeft(temp);
   StringTrimRight(temp);
   return temp;
}

string ToLowerString(const string value)
{
   string temp = value;
   StringToLower(temp);
   return temp;
}

//+------------------------------------------------------------------+
//| 网站授权校验相关                                                  |
//+------------------------------------------------------------------+
bool VerifyAuthorization(const bool force = false)
{
   string cleanedURL = TrimString(AuthServerURL);
   if(cleanedURL == "" || StringLen(cleanedURL) == 0)
   {
      g_isAuthorized = true;
      g_lastAuthCheck = TimeCurrent();
      return true;
   }

   if(!force && g_isAuthorized && (TimeCurrent() - g_lastAuthCheck) < AUTH_RECHECK_INTERVAL)
      return true;

   string trimmedURL = cleanedURL;
   string requestURL = trimmedURL;
   string separator = (StringFind(trimmedURL, "?") >= 0) ? "&" : "?";
   requestURL += separator + "account=" + IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN));

   string tokenClean = TrimString(AUTH_TOKEN);
   if(StringLen(tokenClean) > 0)
      requestURL += "&token=" + tokenClean;

   char data[];
   ArrayResize(data, 0);
   char result[];
   string resultHeaders = "";

   ResetLastError();
   int res = WebRequest("GET", requestURL, "", 5000, data, result, resultHeaders);
   g_lastAuthCheck = TimeCurrent();

   if(res == -1)
   {
      int err = GetLastError();
      g_isAuthorized = false;
      g_lastAuthMessage = StringFormat("WebRequest失败，请在MT5 -> 工具 -> 选项 -> '专家顾问' 中允许URL: %s (错误码=%d)",
                                       trimmedURL, err);
      HandleUnauthorizedState(g_lastAuthMessage);
      return false;
   }

   string body = CharArrayToString(result, 0, ArraySize(result));
   if(ParseAuthorizationResponse(body))
   {
      if(!g_isAuthorized)
         Print("✅ 授权校验通过");
      g_isAuthorized = true;
      g_lastAuthMessage = "授权成功";
      g_authFailedCount = 0;
      return true;
   }

   g_isAuthorized = false;
   g_authFailedCount++;
   if(g_lastAuthMessage == "")
      g_lastAuthMessage = "授权服务器返回未通过: " + body;
   HandleUnauthorizedState(g_lastAuthMessage);
   return false;
}

bool ParseAuthorizationResponse(const string &body)
{
   string lower = ToLowerString(body);
   bool successFlag = (StringFind(lower, "\"success\":true") >= 0);
   bool authorizedFlag = (StringFind(lower, "\"authorized\":true") >= 0);
   bool statusOK = (StringFind(lower, "\"status\":\"ok\"") >= 0);

   if(successFlag || authorizedFlag || statusOK)
      return true;

   // 兼容简单JSON：{"authorized":false,"message":"..."}
   int msgPos = StringFind(lower, "\"message\"");
   if(msgPos >= 0)
      g_lastAuthMessage = body;
   return false;
}

void HandleUnauthorizedState(const string &reason)
{
   Print("❌ 授权失败: ", reason);
   if(BLOCK_WHEN_UNAUTHORIZED)
   {
      Alert("EA授权校验失败：", reason);
   }
}

//+------------------------------------------------------------------+
//| 初始建仓：同时开多0.01与空0.01                                    |
//+------------------------------------------------------------------+
bool ExecuteInitialTrades()
{
   if(!g_isAuthorized)
   {
      Print("❌ 未授权，无法执行初始开仓");
      return false;
   }
   
   // 若已有仓位，尝试恢复
   if(GetPositionCount(true) > 0 || GetPositionCount(false) > 0)
   {
      Print("ℹ️ 检测到已有仓位，尝试恢复状态");
      return true;
   }

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double requiredMargin = CalculateRequiredMargin(InitialLot*2.0);
   if(requiredMargin > balance * 0.9)
   {
      Print("❌ 账户余额不足，无法初始开仓。需要: ", requiredMargin, " 当前: ", balance);
      return false;
   }

   if(!ExecuteTrade(InitialLot, "Init Long", true))
      return false;
   if(!ExecuteTrade(InitialLot, "Init Short", false))
      return false;

   g_long.tradeCount = 1;
   g_short.tradeCount = 1;
   g_long.currentLot = InitialLot;
   g_short.currentLot = InitialLot;

   g_long.firstTradePrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   g_short.firstTradePrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   g_long.lastTradePrice = g_long.firstTradePrice;
   g_short.lastTradePrice = g_short.firstTradePrice;
   g_long.secondLastHedgePrice = g_long.firstTradePrice;
   g_short.secondLastHedgePrice = g_short.firstTradePrice;

   Print("✅ 初始多空建仓完成");
   return true;
}

//+------------------------------------------------------------------+
//| 检查交易条件：哪个方向先达标就先处理                               |
//+------------------------------------------------------------------+
void CheckTradingConditions()
{
   if(!g_isAuthorized) return;
   
   double longProfit = CalculateCurrentProfit(true);
   double shortProfit = CalculateCurrentProfit(false);

   double longTarget = GetFixedProfitTargetByLot(MathMax(CalculateTotalVolume(true), g_long.currentLot>0?g_long.currentLot:InitialLot));
   double shortTarget = GetFixedProfitTargetByLot(MathMax(CalculateTotalVolume(false), g_short.currentLot>0?g_short.currentLot:InitialLot));

   // 优先处理达标的方向；若都达标，先处理浮盈更多的
   bool longHit = longProfit >= longTarget;
   bool shortHit = shortProfit >= shortTarget;

   if(!longHit && !shortHit)
      return;

   if(longHit && shortHit)
   {
      if(longProfit >= shortProfit)
         HandleProfitSide(true);
      else
         HandleProfitSide(false);
   }
   else if(longHit)
   {
      HandleProfitSide(true);
   }
   else if(shortHit)
   {
      HandleProfitSide(false);
   }
}

//+------------------------------------------------------------------+
//| 处理盈利方向：平掉盈利侧 -> 亏损侧加仓 -> 盈利侧按计划重开         |
//+------------------------------------------------------------------+
bool HandleProfitSide(bool profitIsLong)
{
   if(!g_isAuthorized) return false;
   if(isProcessing) return false;
   isProcessing = true;

   string sideName = profitIsLong ? "多" : "空";
   Print("💰 盈利侧(", sideName, ") 达到目标，开始处理");

   // 选择对应状态
   double activeLotBeforeClose = CalculateTotalVolume(profitIsLong);
   if(activeLotBeforeClose <= 0)
   {
      if(profitIsLong)
         activeLotBeforeClose = g_long.currentLot > 0 ? g_long.currentLot : InitialLot;
      else
         activeLotBeforeClose = g_short.currentLot > 0 ? g_short.currentLot : InitialLot;
   }

   // 1) 平掉盈利侧全部仓位
   if(!ClosePositions(profitIsLong))
   {
      Print("❌ 盈利侧平仓失败");
      isProcessing = false;
      return false;
   }

   // 2) 推进盈利序号，规划下次手数
   if(profitIsLong)
      g_long.tradeCount = (g_long.tradeCount <= 0 ? 1 : g_long.tradeCount) + 1;
   else
      g_short.tradeCount = (g_short.tradeCount <= 0 ? 1 : g_short.tradeCount) + 1;

   double plannedReentryLot = GetFixedReentryLot(activeLotBeforeClose);

   if(profitIsLong)
      g_long.currentLot = plannedReentryLot;
   else
      g_short.currentLot = plannedReentryLot;
   Print("📝 盈利侧规划下次开仓手数: ", plannedReentryLot, " (基于本次平仓手数 ", activeLotBeforeClose, ")");

   // 3) 亏损侧加仓（马丁倍增）
   if(!ExecuteHedgeTrade(!profitIsLong))
   {
      Print("❌ 亏损侧加仓失败，停止处理");
      isProcessing = false;
      return false;
   }

   // 4) 盈利侧按规划手数重开（若仍无仓）
   if(GetPositionCount(profitIsLong) == 0 && plannedReentryLot > 0)
   {
      int tradeIndex = profitIsLong ? g_long.tradeCount : g_short.tradeCount;
      string comment = "Profit Reopen " + IntegerToString(tradeIndex);
      if(!ExecuteTrade(plannedReentryLot, comment, profitIsLong))
      {
         Print("❌ 盈利侧重新开仓失败");
         isProcessing = false;
         return false;
      }
      double price = profitIsLong ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(profitIsLong)
      {
         g_long.firstTradePrice = price;
         g_long.lastTradePrice = price;
         g_long.secondLastHedgePrice = price;
      }
      else
      {
         g_short.firstTradePrice = price;
         g_short.lastTradePrice = price;
         g_short.secondLastHedgePrice = price;
      }
      Print("✅ 盈利侧重新开仓成功 手数=", plannedReentryLot, " 价格=", price);
   }
   else
   {
      Print("ℹ️ 盈利侧已有仓位或手数为0，跳过重开");
   }

   isProcessing = false;
   return true;
}

//+------------------------------------------------------------------+
//| 亏损侧加仓：马丁倍增                                               |
//+------------------------------------------------------------------+
bool ExecuteHedgeTrade(bool isLongSide)
{
   if(!g_isAuthorized) return false;
   
   double hedgeLot = 0.0;
   if(isLongSide)
      hedgeLot = CalculateNextHedgeLot(g_long);
   else
      hedgeLot = CalculateNextHedgeLot(g_short);

   if(hedgeLot <= 0)
   {
      Print("❌ 加仓手数无效: ", hedgeLot);
      return false;
   }

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double currentVolume = CalculateTotalVolume(isLongSide);
   double requiredMargin = CalculateRequiredMargin(currentVolume + hedgeLot);
   if(requiredMargin > balance * 0.9)
   {
      Print("❌ 账户余额不足，无法加仓");
      return false;
   }

   int hedgeIndex = isLongSide ? (g_long.hedgeCount + 1) : (g_short.hedgeCount + 1);
   string comment = "Hedge " + IntegerToString(hedgeIndex);
   double price = isLongSide ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(!ExecuteTrade(hedgeLot, comment, isLongSide))
      return false;

   if(isLongSide)
   {
      g_long.hedgeCount++;
      g_long.totalHedgeVolume += hedgeLot;
      if(g_long.lastHedgePrice > 0)
         g_long.secondLastHedgePrice = g_long.lastHedgePrice;
      if(g_long.hedgeCount == 1)
         g_long.firstHedgePrice = price;
      else if(g_long.hedgeCount == 2)
         g_long.secondTradePrice = price;
      g_long.lastHedgePrice = price;
   }
   else
   {
      g_short.hedgeCount++;
      g_short.totalHedgeVolume += hedgeLot;
      if(g_short.lastHedgePrice > 0)
         g_short.secondLastHedgePrice = g_short.lastHedgePrice;
      if(g_short.hedgeCount == 1)
         g_short.firstHedgePrice = price;
      else if(g_short.hedgeCount == 2)
         g_short.secondTradePrice = price;
      g_short.lastHedgePrice = price;
   }

   Print("✅ 亏损侧加仓成功 手数=", hedgeLot, " 总手数=", CalculateTotalVolume(isLongSide));
   return true;
}

//+------------------------------------------------------------------+
//| 重置条件：分别监控多/空，价格回到对应倒数第二仓价即全局重置          |
//+------------------------------------------------------------------+
void CheckResetConditions()
{
   if(!g_isAuthorized) return;
   if(isProcessing) return;

   // 对多、空分别检查
   bool triggered = false;
   ENUM_SIDE triggerSide = SIDE_LONG;
   double triggerPrice = 0;

   for(int s=0; s<2; s++)
   {
      bool isLongSide = (s==0);
      int positionCount = GetPositionCount(isLongSide);
      if(positionCount < 2)
         continue;

      // 读取该侧仓位的开仓价按时间排序
      double openPrices[16];
      datetime openTimes[16];
      int pCount = 0;
      for(int i=0; i<PositionsTotal() && pCount<16; i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket>0 && PositionSelectByTicket(ticket))
         {
            if(PositionGetString(POSITION_SYMBOL)==_Symbol &&
               PositionGetInteger(POSITION_MAGIC)==(isLongSide?MagicNumberLong:MagicNumberShort) &&
               PositionGetInteger(POSITION_TYPE)==(isLongSide?POSITION_TYPE_BUY:POSITION_TYPE_SELL))
            {
               openPrices[pCount] = PositionGetDouble(POSITION_PRICE_OPEN);
               openTimes[pCount] = (datetime)PositionGetInteger(POSITION_TIME);
               pCount++;
            }
         }
      }

      // 排序
      for(int i=0; i<pCount-1; i++)
      {
         for(int j=i+1; j<pCount; j++)
         {
            if(openTimes[j] < openTimes[i])
            {
               datetime t=openTimes[i]; openTimes[i]=openTimes[j]; openTimes[j]=t;
               double p=openPrices[i]; openPrices[i]=openPrices[j]; openPrices[j]=p;
            }
         }
      }

      double targetPrice=0;
      if(positionCount==2 && pCount>=1)
         targetPrice = openPrices[0];
      else if(positionCount==3 && pCount>=2)
         targetPrice = openPrices[1];
      else if(positionCount>=4 && pCount>=2)
         targetPrice = openPrices[pCount-2];

      if(targetPrice<=0) continue;

      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double currentPrice = isLongSide ? bid : ask;

      bool shouldReset = isLongSide ? (currentPrice >= targetPrice) : (currentPrice <= targetPrice);
      if(shouldReset)
      {
         triggered = true;
         triggerSide = isLongSide ? SIDE_LONG : SIDE_SHORT;
         triggerPrice = currentPrice;
         break;
      }
   }

   if(triggered)
   {
     string name = (triggerSide==SIDE_LONG) ? "多" : "空";
     PrintFormat("🔄 触发全局重置 by %s侧，价格回到关键位 %.3f", name, triggerPrice);
     ExecuteGlobalReset();
   }
}

//+------------------------------------------------------------------+
//| 全局重置：平掉所有仓位 -> 重置状态 -> 重新多空0.01                  |
//+------------------------------------------------------------------+
void ExecuteGlobalReset()
{
   if(!g_isAuthorized) return;
   if(isProcessing) return;
   isProcessing = true;

   Print("🔄 全局重置：平掉所有仓位并以0.01多空重新开始");
   // 平仓
   ClosePositions(true);
   ClosePositions(false);

   // 再次尝试确保清空
   int retry=0;
   while((GetPositionCount(true)>0 || GetPositionCount(false)>0) && retry<3)
   {
      ClosePositions(true);
      ClosePositions(false);
      Sleep(300);
      retry++;
   }

   ResetAccountState();
   Sleep(300);
   ExecuteInitialTrades();

   isProcessing = false;
}

//+------------------------------------------------------------------+
//| 交易/手数/辅助                                                     |
//+------------------------------------------------------------------+
double NormalizeLot(double volume)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLotSymbol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double upperBound = MathMin(MaxLot, maxLotSymbol);
   double bounded = MathMax(minLot, MathMin(upperBound, volume));

   if(lotStep > 0)
   {
      double steps = MathRound(bounded / lotStep);
      bounded = steps * lotStep;
      if(bounded > upperBound) bounded = upperBound;
      if(bounded < minLot)     bounded = minLot;
   }

   int lotDigits = 2;
   if(lotStep > 0)
   {
      double stepDigits = -MathLog(lotStep) / MathLog(10.0);
      lotDigits = (int)MathCeil(stepDigits);
      if(lotDigits < 0) lotDigits = 2;
      if(lotDigits > 6) lotDigits = 6;
   }
   return NormalizeDouble(bounded, lotDigits);
}

double GetFixedProfitTargetByLot(double lot)
{
   const double profitPlanLots[]    = {0.01, 0.02, 0.05, 0.11, 0.22, 0.44};
   const double profitPlanTargets[] = {2.0,  6.0, 25.0, 88.0, 220.0, 440.0};

   // 变体规则：手数>=0.32 时，盈利目标=手数*2000
   if(lot >= 0.32)
      return lot * 2000.0;

   for(int i=0;i<ArraySize(profitPlanLots);i++)
   {
      if(MathAbs(lot - profitPlanLots[i]) < 0.0005)
         return profitPlanTargets[i];
   }
   if(lot >= 0.44)
      return lot * 1000.0;
   return MathMax(2.0, lot * 1000.0);
}

double GetFixedReentryLot(double lastLot)
{
   const double profitPlanNextLots[] = {0.02, 0.05, 0.11, 0.22, 0.44, 0.88};
   const double profitPlanLots[]     = {0.01, 0.02, 0.05, 0.11, 0.22, 0.44};
   for(int i=0;i<ArraySize(profitPlanLots);i++)
   {
      if(MathAbs(lastLot - profitPlanLots[i]) < 0.0005)
         return NormalizeLot(profitPlanNextLots[i]);
   }
   if(lastLot >= 0.44)
      return NormalizeLot(lastLot * 2.0);
   return NormalizeLot(InitialLot);
}

double CalculateRequiredMargin(double volume)
{
   double margin = 0;
   if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, volume, SymbolInfoDouble(_Symbol, SYMBOL_ASK), margin))
   {
      long leverage = AccountInfoInteger(ACCOUNT_LEVERAGE);
      margin = volume * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE) * SymbolInfoDouble(_Symbol, SYMBOL_MARGIN_INITIAL) / (double)leverage;
   }
   return margin;
}

double CalculateNextHedgeLot(SideState &state)
{
   int nextIndex = state.hedgeCount + 1;
   double martingaleLot = InitialLot * MathPow(2.0, nextIndex);
   return NormalizeLot(martingaleLot);
}

//+------------------------------------------------------------------+
//| 下单（带填充方式与重试）                                           |
//+------------------------------------------------------------------+
bool ExecuteTrade(double volume, string comment, bool isLongSide)
{
   if(!g_isAuthorized)
   {
      Print("❌ 未授权，无法执行交易");
      return false;
   }
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLotSymbol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   volume = NormalizeLot(volume);
   if(volume < minLot || volume > MaxLot || volume > maxLotSymbol)
   {
      Print("❌ 手数超出限制: ", volume);
      return false;
   }

   if(!TerminalInfoInteger(TERMINAL_CONNECTED))
   {
      Print("❌ 终端未连接，无法下单");
      return false;
   }

   if(!SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE))
   {
      Print("❌ 交易品种不允许交易");
      return false;
   }

   int supportedFilling = (int)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   ENUM_ORDER_TYPE_FILLING fillingModes[] = {ORDER_FILLING_FOK, ORDER_FILLING_IOC, ORDER_FILLING_RETURN};
   if((supportedFilling & SYMBOL_FILLING_FOK) != SYMBOL_FILLING_FOK)
   {
      if((supportedFilling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
         fillingModes[0] = ORDER_FILLING_IOC;
      else if((supportedFilling & SYMBOL_FILLING_BOC) == SYMBOL_FILLING_BOC)
         fillingModes[0] = ORDER_FILLING_RETURN;
   }

   for(int retry=0; retry<OrderExecutionMaxRetries; retry++)
   {
      for(int f=0; f<ArraySize(fillingModes); f++)
      {
         ENUM_ORDER_TYPE_FILLING fill = fillingModes[f];
         bool supported=false;
         if(fill==ORDER_FILLING_FOK   && ((supportedFilling & SYMBOL_FILLING_FOK)!=0)) supported=true;
         if(fill==ORDER_FILLING_IOC   && ((supportedFilling & SYMBOL_FILLING_IOC)!=0)) supported=true;
         if(fill==ORDER_FILLING_RETURN&& ((supportedFilling & SYMBOL_FILLING_BOC)!=0)) supported=true;
         if(!supported) continue;

         MqlTradeRequest req={};
         MqlTradeResult  res={};

         req.action = TRADE_ACTION_DEAL;
         req.symbol = _Symbol;
         req.volume = volume;
         req.deviation = MaxSlippage;
         req.magic = isLongSide ? MagicNumberLong : MagicNumberShort;
         req.comment = comment;
         req.type_filling = fill;

         if(isLongSide)
         {
            req.type = ORDER_TYPE_BUY;
            req.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         }
         else
         {
            req.type = ORDER_TYPE_SELL;
            req.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         }

         if(OrderSend(req, res))
         {
            if(res.retcode==TRADE_RETCODE_DONE || res.retcode==TRADE_RETCODE_PLACED)
            {
               Print("✅ 下单成功 ", comment, " 手数=", volume, " 价格=", res.price, " 填充=", EnumToString(fill));
               return true;
            }
            bool isPartial = (res.volume>0 && res.volume<volume);
            #ifdef TRADE_RETCODE_PARTIAL
            isPartial = isPartial || (res.retcode==TRADE_RETCODE_PARTIAL);
            #endif
            if(isPartial)
            {
               Print("⚠️ 部分成交 ", comment, " 已成交 ", res.volume, "/", volume);
               return true;
            }
            if(res.retcode==TRADE_RETCODE_INVALID_FILL || res.retcode==10044)
               continue;
            if(retry < OrderExecutionMaxRetries-1)
            {
               Sleep(300);
               break;
            }
         }
         else
         {
            int err = GetLastError();
            uint rc = res.retcode;
            if(rc==TRADE_RETCODE_INVALID_FILL || rc==10044 || err==4756)
               continue;
            bool fatal = (err==134 || err==10004);
            #ifdef TRADE_RETCODE_NO_MONEY
            fatal = fatal || (rc==TRADE_RETCODE_NO_MONEY);
            #endif
            #ifdef TRADE_RETCODE_NOT_ENOUGH_MONEY
            fatal = fatal || (rc==TRADE_RETCODE_NOT_ENOUGH_MONEY);
            #endif
            if(fatal) return false;
            if(retry < OrderExecutionMaxRetries-1)
            {
               Sleep(300);
               break;
            }
         }
      }
   }
   Print("❌ 下单最终失败 ", comment);
   return false;
}

//+------------------------------------------------------------------+
//| 统计/平仓                                                         |
//+------------------------------------------------------------------+
int GetPositionCount(bool isLongSide)
{
   int count=0;
   long targetType = isLongSide ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   long targetMagic = isLongSide ? MagicNumberLong : MagicNumberShort;
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket>0 && PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL)==_Symbol &&
            PositionGetInteger(POSITION_MAGIC)==targetMagic &&
            PositionGetInteger(POSITION_TYPE)==targetType)
         {
            count++;
         }
      }
   }
   return count;
}

double CalculateTotalVolume(bool isLongSide)
{
   double total=0;
   long targetType = isLongSide ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   long targetMagic = isLongSide ? MagicNumberLong : MagicNumberShort;
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket>0 && PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL)==_Symbol &&
            PositionGetInteger(POSITION_MAGIC)==targetMagic &&
            PositionGetInteger(POSITION_TYPE)==targetType)
         {
            total += PositionGetDouble(POSITION_VOLUME);
         }
      }
   }
   return total;
}

double CalculateCurrentProfit(bool isLongSide)
{
   double profit=0;
   long targetType = isLongSide ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   long targetMagic = isLongSide ? MagicNumberLong : MagicNumberShort;
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket>0 && PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL)==_Symbol &&
            PositionGetInteger(POSITION_MAGIC)==targetMagic &&
            PositionGetInteger(POSITION_TYPE)==targetType)
         {
            profit += PositionGetDouble(POSITION_PROFIT);
         }
      }
   }
   return profit;
}

bool ClosePositions(bool isLongSide)
{
   int closed=0;
   long targetType = isLongSide ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   long targetMagic = isLongSide ? MagicNumberLong : MagicNumberShort;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket>0 && PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL)==_Symbol &&
            PositionGetInteger(POSITION_MAGIC)==targetMagic &&
            PositionGetInteger(POSITION_TYPE)==targetType)
         {
            MqlTradeRequest req={};
            MqlTradeResult  res={};
            req.action = TRADE_ACTION_DEAL;
            req.symbol = _Symbol;
            req.volume = PositionGetDouble(POSITION_VOLUME);
            req.deviation = MaxSlippage;
            req.magic = targetMagic;
            req.position = ticket;
            req.type_filling = ORDER_FILLING_FOK;

            if(targetType==POSITION_TYPE_BUY)
            {
               req.type = ORDER_TYPE_SELL;
               req.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            }
            else
            {
               req.type = ORDER_TYPE_BUY;
               req.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            }

            if(OrderSend(req, res))
            {
               closed++;
            }
         }
      }
   }
   if(closed>0)
   {
      Print("✅ 平掉 ", (isLongSide?"多":"空"), " 仓位数=", closed);
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| 重置状态                                                         |
//+------------------------------------------------------------------+
void ResetAccountState()
{
   g_long.tradeCount = 0;
   g_long.currentLot = InitialLot;
   g_long.firstTradePrice = 0;
   g_long.lastTradePrice = 0;
   g_long.secondTradePrice = 0;
   g_long.hedgeCount = 0;
   g_long.totalHedgeVolume = 0;
   g_long.firstHedgePrice = 0;
   g_long.lastHedgePrice = 0;
   g_long.secondLastHedgePrice = 0;

   g_short.tradeCount = 0;
   g_short.currentLot = InitialLot;
   g_short.firstTradePrice = 0;
   g_short.lastTradePrice = 0;
   g_short.secondTradePrice = 0;
   g_short.hedgeCount = 0;
   g_short.totalHedgeVolume = 0;
   g_short.firstHedgePrice = 0;
   g_short.lastHedgePrice = 0;
   g_short.secondLastHedgePrice = 0;
   Print("🔄 状态已重置");
}

//+------------------------------------------------------------------+


