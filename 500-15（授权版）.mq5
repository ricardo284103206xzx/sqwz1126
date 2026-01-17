//+------------------------------------------------------------------+
//|                        GoldHedge Conservative Version            |
//|            稳健版单账户双向：500美金本金，抗150美元波动          |
//|        方案1：双向盈亏平衡 + 净值515循环（授权版，仅授权参数）   |
//+------------------------------------------------------------------+
#property copyright "RICARDO.XU"
#property version   "2.20"
#property description "稳健版：保守手数递增，快速盈利平仓，500美金本金 - 双向盈亏平衡 - 净值515循环（授权版）"

#include <Trade\Trade.mqh>

//=== 输入参数（仅授权接口） ===
input string   AuthServerURL        = "https://jsqy.online/api/verify";

//=== 固定配置（已隐藏，需调整请改源码） ===
const double   InitialLot          = 0.01;
const long     MagicNumberBuy      = 88888;
const long     MagicNumberSell     = 88889;
const int      MaxSlippage         = 10;
const int      MaxHedgeLevel       = 8;

const double   HedgeDistanceUSD1   = 5.0;
const double   HedgeDistanceUSD2   = 8.0;
const double   HedgeDistanceUSD3   = 12.0;
const double   HedgeDistanceUSD4   = 15.0;
const double   HedgeDistanceUSD5Plus = 20.0;
const int      MinHedgeIntervalSec = 10;

const double   ProfitThreshold1    = 0.5;
const double   ProfitThreshold2    = 1.0;
const double   ProfitThreshold3    = 1.5;
const double   ProfitThreshold4    = 2.0;
const double   ProfitThreshold5Plus = 2.5;

const bool     EnableBalanceMode    = true;
const double   BalanceThreshold     = 0.0;

const bool     EnableEquityTarget   = true;
const double   EquityTarget         = 515.0;

const double   MaxDrawdownUSD      = 80.0;
const double   MaxDrawdownCritical = 120.0;

// 授权隐藏配置
const string   AUTH_TOKEN               = "";
const int      AUTH_RECHECK_INTERVAL    = 0;    // 0=仅启动时校验
const bool     BLOCK_WHEN_UNAUTHORIZED  = true;

//=== 状态结构 ===
struct SideState
{
   bool    initialized;
   int     hedgeLevel;
   double  firstTradePrice;
   double  lastHedgePrice;
   double  nextHedgeLot;
   datetime lastTradeTime;
   bool    isClosing;
   bool    isHedging;
   double  totalVolume;
};

SideState g_buy  = {false,0,0,0,0.01,0,false,false,0};
SideState g_sell = {false,0,0,0,0.01,0,false,false,0};

datetime lastPrint = 0;
CTrade   trade;
bool     g_stopped = false;  // 是否已达到目标并停止

// 授权相关全局变量
bool     g_isAuthorized = false;
datetime g_lastAuthCheck = 0;
int      g_authFailedCount = 0;
string   g_lastAuthMessage = "";

//=== 前置声明 ===
int    CountPositions(bool isBuy);
double CalculateProfit(bool isBuy);
double CalculateTotalVolume(bool isBuy);
double CalculateDrawdown(bool isBuy);
bool   OpenOrder(bool isBuy, double lot, string comment);
void   CloseAll(bool isBuy);
void   CloseAllPositions();
double CalcNextHedgeLot(int hedgeLevel);
double GetHedgeDistanceUSD(int hedgeLevel);
void   InitIfNeeded();
void   CheckProfitSide(bool isBuy);
void   CheckHedgeSide(bool isBuy);
bool   CheckRiskControl(bool isBuy);
void   CheckEquityTarget();

// 授权相关
string TrimString(const string value);
string ToLowerString(const string value);
bool   VerifyAuthorization(const bool force = false);
bool   ParseAuthorizationResponse(const string &body);
void   HandleUnauthorizedState(const string &reason);

//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== 稳健版马丁EA启动（500美金本金）- 方案1：双向盈亏平衡 + 净值515循环 - 授权版 ===");
   if(!VerifyAuthorization(true))
   {
      Print("❌ 授权校验失败，原因: ", g_lastAuthMessage);
      MessageBox("授权校验失败，请检查网站授权或网络连接。\n错误详情: " + g_lastAuthMessage,
                 "授权失败", MB_ICONSTOP);
      return INIT_FAILED;
   }
   
   if(InitialLot <= 0)
   {
      Print("❌ 初始手数无效: ", InitialLot);
      return INIT_PARAMETERS_INCORRECT;
   }
   
   InitIfNeeded();
   EventSetTimer(1);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   Print("EA停止，原因: ", reason);
}

//+------------------------------------------------------------------+
void OnTimer()
{
   if(AUTH_RECHECK_INTERVAL > 0 && (TimeCurrent() - g_lastAuthCheck) >= AUTH_RECHECK_INTERVAL)
      VerifyAuthorization(true);
   if(!g_isAuthorized) return;

   if(EnableEquityTarget)
      CheckEquityTarget();

   if(g_stopped) return;

   InitIfNeeded();
   CheckProfitSide(true);
   CheckProfitSide(false);
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(!g_isAuthorized || g_stopped) return;
   CheckHedgeSide(true);
   CheckHedgeSide(false);
}

//=== 授权工具 ===
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

   string requestURL = cleanedURL;
   string separator = (StringFind(cleanedURL, "?") >= 0) ? "&" : "?";
   requestURL += separator + "account=" + IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN));
   string tokenClean = TrimString(AUTH_TOKEN);
   if(StringLen(tokenClean) > 0)
      requestURL += "&token=" + tokenClean;

   char data[]; ArrayResize(data, 0);
   char result[];
   string headers = "";

   ResetLastError();
   int res = WebRequest("GET", requestURL, "", 5000, data, result, headers);
   g_lastAuthCheck = TimeCurrent();

   if(res == -1)
   {
      int err = GetLastError();
      g_isAuthorized = false;
      g_lastAuthMessage = StringFormat("WebRequest失败，请在MT5 -> 工具 -> 选项 -> '专家顾问' 中允许URL: %s (错误码=%d)",
                                       cleanedURL, err);
      HandleUnauthorizedState(g_lastAuthMessage);
      return false;
   }

   string body = CharArrayToString(result, 0, ArraySize(result));
   if(ParseAuthorizationResponse(body))
   {
      if(!g_isAuthorized) Print("✅ 授权校验通过");
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
   bool successFlag    = (StringFind(lower, "\"success\":true") >= 0);
   bool authorizedFlag = (StringFind(lower, "\"authorized\":true") >= 0);
   bool statusOK       = (StringFind(lower, "\"status\":\"ok\"") >= 0);
   if(successFlag || authorizedFlag || statusOK)
      return true;
   int msgPos = StringFind(lower, "\"message\"");
   if(msgPos >= 0)
      g_lastAuthMessage = body;
   return false;
}

void HandleUnauthorizedState(const string &reason)
{
   Print("❌ 授权失败: ", reason);
   if(BLOCK_WHEN_UNAUTHORIZED)
      Alert("EA授权校验失败：", reason);
}

//=== 核心逻辑 ===
void CheckEquityTarget()
{
   if(g_stopped) return;
   if(g_buy.isClosing || g_sell.isClosing) return;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   static datetime lastEquityLog = 0;
   if(TimeCurrent() - lastEquityLog >= 60)
   {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double profit = CalculateProfit(true) + CalculateProfit(false);
      PrintFormat("💰 账户状态: 余额=%.2f 净值=%.2f 浮动盈亏=%.2f 目标=%.2f",
                  balance, equity, profit, EquityTarget);
      lastEquityLog = TimeCurrent();
   }

   if(equity >= EquityTarget)
   {
      PrintFormat("🎯 净值达到目标！净值=%.2f >= %.2f，全部平仓并停止", equity, EquityTarget);
      g_stopped = true;
      g_buy.isClosing = true;
      g_sell.isClosing = true;
      CloseAllPositions();
      int maxWait = 50;
      while((CountPositions(true) > 0 || CountPositions(false) > 0) && maxWait-- > 0)
      {
         Sleep(100);
      }
      double finalEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      double finalBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      PrintFormat("✅ 全部平仓完成！余额=%.2f 净值=%.2f", finalBalance, finalEquity);
      Print("🛑 EA已停止所有操作");
   }
}

void InitIfNeeded()
{
   if(g_stopped) return;

   // 多侧
   if(!g_buy.initialized)
   {
      int buyCount = CountPositions(true);
      if(buyCount > 0)
      {
         double minPrice = DBL_MAX;
         double totalVol = 0;
         for(int i=0; i<PositionsTotal(); i++)
         {
            ulong ticket = PositionGetTicket(i);
            if(ticket>0 && PositionSelectByTicket(ticket))
            {
               if(PositionGetInteger(POSITION_MAGIC)==MagicNumberBuy &&
                  PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY &&
                  PositionGetString(POSITION_SYMBOL)==_Symbol)
               {
                  double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
                  double volume = PositionGetDouble(POSITION_VOLUME);
                  if(openPrice < minPrice) minPrice = openPrice;
                  totalVol += volume;
               }
            }
         }
         if(minPrice != DBL_MAX)
         {
            g_buy.firstTradePrice = minPrice;
            g_buy.lastHedgePrice = minPrice;
            g_buy.initialized = true;
            g_buy.hedgeLevel = buyCount - 1;
            g_buy.totalVolume = totalVol;
            g_buy.nextHedgeLot = CalcNextHedgeLot(g_buy.hedgeLevel);
            PrintFormat("✅ 多侧恢复：持仓=%d 基准价=%.2f 累计手数=%.2f", buyCount, g_buy.firstTradePrice, g_buy.totalVolume);
         }
      }
      else
      {
         if(OpenOrder(true, InitialLot, "Init Buy"))
         {
            g_buy.firstTradePrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            g_buy.lastHedgePrice = g_buy.firstTradePrice;
            g_buy.initialized = true;
            g_buy.hedgeLevel = 0;
            g_buy.nextHedgeLot = CalcNextHedgeLot(0);
            g_buy.totalVolume = InitialLot;
            Print("✅ 初始多单开仓成功 价=", g_buy.firstTradePrice);
         }
      }
   }

   // 空侧
   if(!g_sell.initialized)
   {
      int sellCount = CountPositions(false);
      if(sellCount > 0)
      {
         double maxPrice = 0;
         double totalVol = 0;
         for(int i=0; i<PositionsTotal(); i++)
         {
            ulong ticket = PositionGetTicket(i);
            if(ticket>0 && PositionSelectByTicket(ticket))
            {
               if(PositionGetInteger(POSITION_MAGIC)==MagicNumberSell &&
                  PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_SELL &&
                  PositionGetString(POSITION_SYMBOL)==_Symbol)
               {
                  double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
                  double volume = PositionGetDouble(POSITION_VOLUME);
                  if(openPrice > maxPrice) maxPrice = openPrice;
                  totalVol += volume;
               }
            }
         }
         if(maxPrice > 0)
         {
            g_sell.firstTradePrice = maxPrice;
            g_sell.lastHedgePrice = maxPrice;
            g_sell.initialized = true;
            g_sell.hedgeLevel = sellCount - 1;
            g_sell.totalVolume = totalVol;
            g_sell.nextHedgeLot = CalcNextHedgeLot(g_sell.hedgeLevel);
            PrintFormat("✅ 空侧恢复：持仓=%d 基准价=%.2f 累计手数=%.2f", sellCount, g_sell.firstTradePrice, g_sell.totalVolume);
         }
      }
      else
      {
         if(OpenOrder(false, InitialLot, "Init Sell"))
         {
            g_sell.firstTradePrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            g_sell.lastHedgePrice = g_sell.firstTradePrice;
            g_sell.initialized = true;
            g_sell.hedgeLevel = 0;
            g_sell.nextHedgeLot = CalcNextHedgeLot(0);
            g_sell.totalVolume = InitialLot;
            Print("✅ 初始空单开仓成功 价=", g_sell.firstTradePrice);
         }
      }
   }
}

void CheckProfitSide(bool isBuy)
{
   if(g_stopped) return;
   bool initialized = isBuy ? g_buy.initialized : g_sell.initialized;
   bool isClosing   = isBuy ? g_buy.isClosing   : g_sell.isClosing;
   if(!initialized || isClosing) return;

   int positionCount = CountPositions(isBuy);
   if(positionCount == 0) return;

   double profit = CalculateProfit(isBuy);
   int hedgeLevel = isBuy ? g_buy.hedgeLevel : g_sell.hedgeLevel;

   if(TimeCurrent() - lastPrint >= 30)
   {
      double drawdown = CalculateDrawdown(isBuy);
      double oppositeProfit = CalculateProfit(!isBuy);
      double totalProfit = profit + oppositeProfit;
      PrintFormat("%s侧 状态: 盈利=%.2f 持仓=%d 加仓=%d 浮亏=%.2f | 对侧=%.2f 总盈亏=%.2f",
                  isBuy?"多":"空", profit, positionCount, hedgeLevel, drawdown, oppositeProfit, totalProfit);
      lastPrint = TimeCurrent();
   }

   double threshold = 0;
   if(positionCount == 1)      threshold = ProfitThreshold1;
   else if(positionCount == 2) threshold = ProfitThreshold2;
   else if(positionCount == 3) threshold = ProfitThreshold3;
   else if(positionCount == 4) threshold = ProfitThreshold4;
   else if(positionCount >= 5) threshold = ProfitThreshold5Plus;

   bool shouldClose = false;
   string reason = "";

   if(EnableBalanceMode)
   {
      double oppositeProfit = CalculateProfit(!isBuy);
      double totalProfit = profit + oppositeProfit;
      if(profit >= threshold && totalProfit >= BalanceThreshold)
      {
         shouldClose = true;
         reason = StringFormat("持仓=%d 盈利=%.2f 对侧=%.2f 总盈亏=%.2f >= %.2f",
                               positionCount, profit, oppositeProfit, totalProfit, BalanceThreshold);
      }
      else if(profit >= threshold)
      {
         static datetime lastBalanceLog = 0;
         if(TimeCurrent() - lastBalanceLog >= 60)
         {
            PrintFormat("⏸️ %s侧盈利 %.2f 但总盈亏不足，等待回调", isBuy?"多":"空", profit);
            lastBalanceLog = TimeCurrent();
         }
      }
   }
   else
   {
      if(profit >= threshold)
      {
         shouldClose = true;
         reason = StringFormat("持仓=%d 盈利>=%.2f", positionCount, threshold);
      }
   }

   if(!shouldClose) return;

   if(isBuy) g_buy.isClosing = true; else g_sell.isClosing = true;
   PrintFormat("💵 %s侧平仓: %s", isBuy?"多":"空", reason);
   CloseAll(isBuy);

   if(isBuy)
   {
      g_buy.initialized   = false;
      g_buy.hedgeLevel    = 0;
      g_buy.firstTradePrice = 0;
      g_buy.lastHedgePrice  = 0;
      g_buy.nextHedgeLot    = InitialLot;
      g_buy.lastTradeTime   = 0;
      g_buy.isClosing       = false;
      g_buy.isHedging       = false;
      g_buy.totalVolume     = 0;
   }
   else
   {
      g_sell.initialized   = false;
      g_sell.hedgeLevel    = 0;
      g_sell.firstTradePrice = 0;
      g_sell.lastHedgePrice  = 0;
      g_sell.nextHedgeLot    = InitialLot;
      g_sell.lastTradeTime   = 0;
      g_sell.isClosing       = false;
      g_sell.isHedging       = false;
      g_sell.totalVolume     = 0;
   }
   InitIfNeeded();
}

void CheckHedgeSide(bool isBuy)
{
   if(g_stopped) return;
   bool initialized = isBuy ? g_buy.initialized : g_sell.initialized;
   bool isClosing   = isBuy ? g_buy.isClosing   : g_sell.isClosing;
   bool isHedging   = isBuy ? g_buy.isHedging   : g_sell.isHedging;
   if(!initialized || isClosing || isHedging) return;
   if(!CheckRiskControl(isBuy)) return;

   int positionCount = CountPositions(isBuy);
   if(positionCount == 0) return;
   int hedgeLevel = isBuy ? g_buy.hedgeLevel : g_sell.hedgeLevel;
   if(hedgeLevel >= MaxHedgeLevel) return;

   double lastHedgePrice = isBuy ? g_buy.lastHedgePrice : g_sell.lastHedgePrice;
   datetime lastTradeTime = isBuy ? g_buy.lastTradeTime : g_sell.lastTradeTime;
   double nextHedgeLot = isBuy ? g_buy.nextHedgeLot : g_sell.nextHedgeLot;
   if(TimeCurrent() - lastTradeTime < MinHedgeIntervalSec) return;

   double currentPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double priceDiffPoints = MathAbs((isBuy ? (lastHedgePrice - currentPrice) : (currentPrice - lastHedgePrice)) / _Point);
   double priceDiffUSD = priceDiffPoints * tickValue * InitialLot;
   double requiredDistanceUSD = GetHedgeDistanceUSD(hedgeLevel);

   static datetime lastDbg = 0;
   if(TimeCurrent() - lastDbg >= 10)
   {
      PrintFormat("%s侧加仓检查: 当前价=%.2f 基准=%.2f 价差=%.2fUSD 需=%.2fUSD 层数=%d",
                  isBuy?"多":"空", currentPrice, lastHedgePrice, priceDiffUSD, requiredDistanceUSD, hedgeLevel);
      lastDbg = TimeCurrent();
   }

   if(priceDiffUSD < requiredDistanceUSD) return;

   if(isBuy) g_buy.isHedging = true; else g_sell.isHedging = true;

   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double normalizedLot = MathFloor(nextHedgeLot / lotStep) * lotStep;
   normalizedLot = NormalizeDouble(normalizedLot, 2);
   if(normalizedLot < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
   {
      PrintFormat("❌ 手数 %.2f 小于最小手数，跳过加仓", normalizedLot);
      if(isBuy) g_buy.isHedging = false; else g_sell.isHedging = false;
      return;
   }

   PrintFormat("📈 %s侧执行第%d次加仓 手数=%.2f 价差=%.2fUSD",
               isBuy?"多":"空", hedgeLevel+1, normalizedLot, priceDiffUSD);

   if(OpenOrder(isBuy, normalizedLot, "Hedge "+IntegerToString(hedgeLevel+1)))
   {
      double actualPrice = trade.ResultPrice();
      if(actualPrice <= 0)
      {
         actualPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
         PrintFormat("⚠️ 无法获取成交价，使用当前报价: %.2f", actualPrice);
      }

      if(isBuy)
      {
         g_buy.hedgeLevel++;
         g_buy.nextHedgeLot = CalcNextHedgeLot(g_buy.hedgeLevel);
         g_buy.lastHedgePrice = actualPrice;
         g_buy.lastTradeTime = TimeCurrent();
         g_buy.totalVolume += normalizedLot;
         PrintFormat("✅ 多侧加仓成功 成交价=%.2f 新基准=%.2f 累计手数=%.2f",
                    actualPrice, g_buy.lastHedgePrice, g_buy.totalVolume);
      }
      else
      {
         g_sell.hedgeLevel++;
         g_sell.nextHedgeLot = CalcNextHedgeLot(g_sell.hedgeLevel);
         g_sell.lastHedgePrice = actualPrice;
         g_sell.lastTradeTime = TimeCurrent();
         g_sell.totalVolume += normalizedLot;
         PrintFormat("✅ 空侧加仓成功 成交价=%.2f 新基准=%.2f 累计手数=%.2f",
                    actualPrice, g_sell.lastHedgePrice, g_sell.totalVolume);
      }
   }
   if(isBuy) g_buy.isHedging = false; else g_sell.isHedging = false;
}

bool CheckRiskControl(bool isBuy)
{
   double drawdown = CalculateDrawdown(isBuy);
   if(drawdown >= MaxDrawdownCritical)
   {
      static datetime lastWarn = 0;
      if(TimeCurrent() - lastWarn >= 60)
      {
         PrintFormat("⚠️ %s侧浮亏 %.2f 达到临界值，停止加仓", isBuy?"多":"空", drawdown);
         lastWarn = TimeCurrent();
      }
      return false;
   }
   if(drawdown >= MaxDrawdownUSD)
   {
      static datetime lastWarn = 0;
      if(TimeCurrent() - lastWarn >= 60)
      {
         PrintFormat("⚠️ %s侧浮亏 %.2f 达到限制，停止加仓", isBuy?"多":"空", drawdown);
         lastWarn = TimeCurrent();
      }
      return false;
   }
   return true;
}

double CalcNextHedgeLot(int hedgeLevel)
{
   double newLot = InitialLot;
   if(hedgeLevel == 0)      newLot = InitialLot;
   else if(hedgeLevel == 1) newLot = InitialLot;
   else if(hedgeLevel == 2) newLot = InitialLot * 2.0;
   else if(hedgeLevel == 3) newLot = InitialLot * 2.0;
   else if(hedgeLevel == 4) newLot = InitialLot * 3.0;
   else if(hedgeLevel == 5) newLot = InitialLot * 3.0;
   else                     newLot = InitialLot * 4.0;
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   newLot = MathFloor(newLot / lotStep) * lotStep;
   return NormalizeDouble(newLot, 2);
}

double GetHedgeDistanceUSD(int hedgeLevel)
{
   if(hedgeLevel == 0) return HedgeDistanceUSD1;
   else if(hedgeLevel == 1) return HedgeDistanceUSD2;
   else if(hedgeLevel == 2) return HedgeDistanceUSD3;
   else if(hedgeLevel == 3) return HedgeDistanceUSD4;
   return HedgeDistanceUSD5Plus;
}

int CountPositions(bool isBuy)
{
   int count = 0;
   long targetType = isBuy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   long targetMagic = isBuy ? MagicNumberBuy : MagicNumberSell;
   for(int i=0; i<PositionsTotal(); i++)
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

double CalculateProfit(bool isBuy)
{
   double profit = 0;
   long targetType = isBuy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   long targetMagic = isBuy ? MagicNumberBuy : MagicNumberSell;
   for(int i=0; i<PositionsTotal(); i++)
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

double CalculateTotalVolume(bool isBuy)
{
   double totalVol = 0;
   long targetType = isBuy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   long targetMagic = isBuy ? MagicNumberBuy : MagicNumberSell;
   for(int i=0; i<PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket>0 && PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL)==_Symbol &&
            PositionGetInteger(POSITION_MAGIC)==targetMagic &&
            PositionGetInteger(POSITION_TYPE)==targetType)
         {
            totalVol += PositionGetDouble(POSITION_VOLUME);
         }
      }
   }
   return totalVol;
}

double CalculateDrawdown(bool isBuy)
{
   double profit = CalculateProfit(isBuy);
   if(profit < 0) return -profit;
   return 0;
}

bool OpenOrder(bool isBuy, double lot, string comment)
{
   if(!g_isAuthorized)
   {
      Print("❌ 未授权，无法执行交易");
      return false;
   }

   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lot < minLot || lot > maxLot)
   {
      PrintFormat("❌ 手数 %.2f 超出范围 [%.2f, %.2f]", lot, minLot, maxLot);
      return false;
   }

   trade.SetExpertMagicNumber(isBuy ? MagicNumberBuy : MagicNumberSell);
   trade.SetDeviationInPoints(MaxSlippage);

   ENUM_ORDER_TYPE_FILLING filling = (ENUM_ORDER_TYPE_FILLING)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & ORDER_FILLING_FOK) == ORDER_FILLING_FOK)      trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((filling & ORDER_FILLING_IOC) == ORDER_FILLING_IOC) trade.SetTypeFilling(ORDER_FILLING_IOC);
   else                                                        trade.SetTypeFilling(ORDER_FILLING_RETURN);

   bool result = isBuy ? trade.Buy(lot, _Symbol, 0, 0, 0, comment)
                       : trade.Sell(lot, _Symbol, 0, 0, 0, comment);
   if(result)
   {
      double price = trade.ResultPrice();
      ulong order = trade.ResultOrder();
      PrintFormat("✅ 下单成功 %s 手数=%.2f 成交价=%.2f 订单号=%I64u", comment, lot, price, order);
      return true;
   }
   else
   {
      uint retcode = trade.ResultRetcode();
      string desc = trade.ResultRetcodeDescription();
      PrintFormat("❌ 下单失败 %s 手数=%.2f 错误码=%u %s", comment, lot, retcode, desc);
      return false;
   }
}

void CloseAll(bool isBuy)
{
   long targetType = isBuy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   long targetMagic = isBuy ? MagicNumberBuy : MagicNumberSell;
   int closed=0, total=0;
   for(int i=0; i<PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket>0 && PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL)==_Symbol &&
            PositionGetInteger(POSITION_MAGIC)==targetMagic &&
            PositionGetInteger(POSITION_TYPE)==targetType)
            total++;
      }
   }

   trade.SetExpertMagicNumber(targetMagic);
   trade.SetDeviationInPoints(MaxSlippage);

   int attempts = 0;
   while(closed < total && attempts < 100)
   {
      bool found=false;
      for(int i=PositionsTotal()-1; i>=0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket>0 && PositionSelectByTicket(ticket))
         {
            if(PositionGetString(POSITION_SYMBOL)==_Symbol &&
               PositionGetInteger(POSITION_MAGIC)==targetMagic &&
               PositionGetInteger(POSITION_TYPE)==targetType)
            {
               double volume = PositionGetDouble(POSITION_VOLUME);
               bool ok = trade.PositionClose(ticket);
               if(ok)
               {
                  closed++; found=true;
                  PrintFormat("✅ 平仓成功 订单号=%I64u 手数=%.2f", ticket, volume);
                  break;
               }
               else
               {
                  uint rc = trade.ResultRetcode();
                  PrintFormat("❌ 平仓失败 订单号=%I64u 错误=%u", ticket, rc);
               }
            }
         }
      }
      if(!found) break;
      attempts++;
      Sleep(100);
   }
   PrintFormat("✅ 已平掉 %s侧 仓位数=%d/%d", (isBuy ? "多" : "空"), closed, total);
}

void CloseAllPositions()
{
   int closed=0, total=0;
   for(int i=0; i<PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket>0 && PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL)==_Symbol &&
            (PositionGetInteger(POSITION_MAGIC)==MagicNumberBuy ||
             PositionGetInteger(POSITION_MAGIC)==MagicNumberSell))
            total++;
      }
   }

   trade.SetDeviationInPoints(MaxSlippage);

   int attempts=0;
   while(closed < total && attempts < 100)
   {
      bool found=false;
      for(int i=PositionsTotal()-1; i>=0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket>0 && PositionSelectByTicket(ticket))
         {
            if(PositionGetString(POSITION_SYMBOL)==_Symbol &&
               (PositionGetInteger(POSITION_MAGIC)==MagicNumberBuy ||
                PositionGetInteger(POSITION_MAGIC)==MagicNumberSell))
            {
               long magic = PositionGetInteger(POSITION_MAGIC);
               trade.SetExpertMagicNumber(magic);
               double volume = PositionGetDouble(POSITION_VOLUME);
               bool ok = trade.PositionClose(ticket);
               if(ok) { closed++; found=true; PrintFormat("✅ 平仓成功 订单号=%I64u 手数=%.2f", ticket, volume); break; }
               else   { uint rc=trade.ResultRetcode(); PrintFormat("❌ 平仓失败 订单号=%I64u 错误=%u", ticket, rc); }
            }
         }
      }
      if(!found) break;
      attempts++;
      Sleep(100);
   }
   PrintFormat("✅ 已平掉所有持仓 %d/%d", closed, total);
}

// 统一 NormalizeLot / NormalizeDouble 使用
double NormalizeLot(double volume)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLotSymbol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double upperBound = MathMin(maxLotSymbol, volume);
   double bounded = MathMax(minLot, MathMin(upperBound, volume));
   if(lotStep > 0)
   {
      double steps = MathFloor(bounded / lotStep);
      bounded = steps * lotStep;
   }
   return NormalizeDouble(bounded, 2);
}

//+------------------------------------------------------------------+

