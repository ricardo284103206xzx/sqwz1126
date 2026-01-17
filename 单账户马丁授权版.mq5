//+------------------------------------------------------------------+
//|                           GoldHedge Single Account               |
//|            马丁速平版单账户双向：同一账户同时持有多与空            |
//|            授权版：集成网站授权验证                               |
//+------------------------------------------------------------------+
#property copyright "RICARDO.XU"
#property version   "3.0"
#property description "单账户双向版：基于速平版逻辑，去除双账户共享文件 - 授权版"

#include <Trade\Trade.mqh>

//=== 输入参数（仅授权接口） ===
input string   AuthServerURL        = "https://jsqy.online/api/verify";

//=== 固定配置（已隐藏） ===
const double   InitialLot          = 0.01;        // 初始手数
const long     MagicNumberBuy      = 88888;       // 多单魔术码
const long     MagicNumberSell     = 88889;       // 空单魔术码
const int      MaxSlippage         = 10;          // 下单滑点
const int      MaxHedgeLevel       = 8;           // 最大加仓次数
const int      MinHedgeIntervalSec = 10;          // 加仓最小间隔秒

// 授权隐藏配置（可在源码中修改，终端输入参数中不可见）
const string   AUTH_TOKEN               = "";       // 可选：额外校验令牌
const int      AUTH_RECHECK_INTERVAL    = 0;        // 0=仅启动时校验，不再定期重检
const bool     BLOCK_WHEN_UNAUTHORIZED  = true;     // 未授权时是否阻止交易

// 盈利平仓阈值（与原版一致）
#define PROFIT_THRESHOLD_LOW_POSITIONS   0.5   // 持仓<3
#define PROFIT_THRESHOLD_3_POSITIONS     0.1   // 持仓=3
#define PROFIT_THRESHOLD_HIGH_POSITIONS -3.0   // 持仓>=4

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
};

SideState g_buy  = {false,0,0,0,0.02,0,false,false};
SideState g_sell = {false,0,0,0,0.02,0,false,false};

datetime lastPrint = 0;

// 授权相关全局变量
bool     g_isAuthorized = false;
datetime g_lastAuthCheck = 0;
int      g_authFailedCount = 0;
string   g_lastAuthMessage = "";

//=== 前置声明 ===
int    CountPositions(bool isBuy);
double CalculateProfit(bool isBuy);
bool   OpenOrder(bool isBuy, double lot, string comment);
void   CloseAll(bool isBuy);
double CalcNextHedgeLot(double currentLot);
void   InitIfNeeded();
void   CheckProfitSide(bool isBuy);
void   CheckHedgeSide(bool isBuy);

// 授权相关函数
string TrimString(const string value);
string ToLowerString(const string value);
bool   VerifyAuthorization(const bool force = false);
bool   ParseAuthorizationResponse(const string &body);
void   HandleUnauthorizedState(const string &reason);

//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== 单账户双向马丁速平版启动 - 授权版 ===");
   
   if(!VerifyAuthorization(true))
   {
      Print("❌ 授权校验失败，原因: ", g_lastAuthMessage);
      MessageBox("授权校验失败，请检查网站授权或网络连接。\n错误详情: " + g_lastAuthMessage,
                 "授权失败", MB_ICONSTOP);
      return INIT_FAILED;
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
   
   if(!g_isAuthorized)
      return;
      
   InitIfNeeded();          // 确保初始多空存在
   CheckProfitSide(true);   // 检查多侧盈利平仓
   CheckProfitSide(false);  // 检查空侧盈利平仓
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(!g_isAuthorized)
      return;
      
   // 价格变动时检查加仓
   CheckHedgeSide(true);
   CheckHedgeSide(false);
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
void InitIfNeeded()
{
   if(!g_isAuthorized) return;
   
   // 如果多侧未初始化，先检查是否已有多单仓位恢复状态，否则开仓
   if(!g_buy.initialized)
   {
      int buyCount = CountPositions(true);
      if(buyCount > 0)
      {
         // 恢复首单价与状态
         for(int i=0;i<PositionsTotal();i++)
         {
            ulong ticket = PositionGetTicket(i);
            if(ticket>0 && PositionSelectByTicket(ticket))
            {
               if(PositionGetInteger(POSITION_MAGIC)==MagicNumberBuy &&
                  PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY &&
                  PositionGetString(POSITION_SYMBOL)==_Symbol)
               {
                  g_buy.firstTradePrice = PositionGetDouble(POSITION_PRICE_OPEN);
                  g_buy.lastHedgePrice = g_buy.firstTradePrice;
                  g_buy.initialized = true;
                  g_buy.hedgeLevel = 0;
                  g_buy.nextHedgeLot = 0.02;
                  break;
               }
            }
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
            g_buy.nextHedgeLot = 0.02;
            Print("✅ 初始多单开仓成功 价=", g_buy.firstTradePrice);
         }
      }
   }

   // 如果空侧未初始化
   if(!g_sell.initialized)
   {
      int sellCount = CountPositions(false);
      if(sellCount > 0)
      {
         for(int i=0;i<PositionsTotal();i++)
         {
            ulong ticket = PositionGetTicket(i);
            if(ticket>0 && PositionSelectByTicket(ticket))
            {
               if(PositionGetInteger(POSITION_MAGIC)==MagicNumberSell &&
                  PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_SELL &&
                  PositionGetString(POSITION_SYMBOL)==_Symbol)
               {
                  g_sell.firstTradePrice = PositionGetDouble(POSITION_PRICE_OPEN);
                  g_sell.lastHedgePrice = g_sell.firstTradePrice;
                  g_sell.initialized = true;
                  g_sell.hedgeLevel = 0;
                  g_sell.nextHedgeLot = 0.02;
                  break;
               }
            }
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
            g_sell.nextHedgeLot = 0.02;
            Print("✅ 初始空单开仓成功 价=", g_sell.firstTradePrice);
         }
      }
   }
}

//+------------------------------------------------------------------+
// 盈利平仓：独立检查多/空
//+------------------------------------------------------------------+
void CheckProfitSide(bool isBuy)
{
   if(!g_isAuthorized) return;
   
   bool initialized = isBuy ? g_buy.initialized : g_sell.initialized;
   bool isClosing   = isBuy ? g_buy.isClosing   : g_sell.isClosing;
   if(!initialized) return;
   if(isClosing) return;

   int positionCount = CountPositions(isBuy);
   double profit = CalculateProfit(isBuy);

   int hedgeLevel = isBuy ? g_buy.hedgeLevel : g_sell.hedgeLevel;

   // 调试日志节流
   if(TimeCurrent() - lastPrint >= 30)
   {
      PrintFormat("%s侧 状态: 盈利=%.2f 持仓=%d 加仓=%d", isBuy?"多":"空", profit, positionCount, hedgeLevel);
      lastPrint = TimeCurrent();
   }

   bool shouldClose=false;
   string reason="";

   if(positionCount < 3)
   {
      if(profit >= PROFIT_THRESHOLD_LOW_POSITIONS)
      {
         shouldClose=true;
         reason="持仓<3 盈利>=0.5";
      }
   }
   else if(positionCount == 3)
   {
      if(profit >= PROFIT_THRESHOLD_3_POSITIONS)
      {
         shouldClose=true;
         reason="持仓=3 盈利>=0.1";
      }
   }
   else if(positionCount >= 4)
   {
      if(profit > PROFIT_THRESHOLD_HIGH_POSITIONS)
      {
         shouldClose=true;
         reason="持仓>=4 盈利>-3";
      }
   }

   if(!shouldClose) return;

   if(isBuy) g_buy.isClosing = true; else g_sell.isClosing = true;
   PrintFormat("💵 %s侧平仓: %s 当前盈利=%.2f 持仓=%d", isBuy?"多":"空", reason, profit, positionCount);

   CloseAll(isBuy);

   // 重置并重新开初始仓
   if(isBuy)
   {
      g_buy.initialized = false;
      g_buy.hedgeLevel = 0;
      g_buy.nextHedgeLot = 0.02;
      g_buy.lastHedgePrice = 0;
      g_buy.firstTradePrice = 0;
      g_buy.lastTradeTime = 0;
      g_buy.isClosing = false;
   }
   else
   {
      g_sell.initialized = false;
      g_sell.hedgeLevel = 0;
      g_sell.nextHedgeLot = 0.02;
      g_sell.lastHedgePrice = 0;
      g_sell.firstTradePrice = 0;
      g_sell.lastTradeTime = 0;
      g_sell.isClosing = false;
   }

   InitIfNeeded();
}

//+------------------------------------------------------------------+
// 加仓：独立检查多/空
//+------------------------------------------------------------------+
void CheckHedgeSide(bool isBuy)
{
   if(!g_isAuthorized) return;
   
   bool initialized = isBuy ? g_buy.initialized : g_sell.initialized;
   bool isClosing   = isBuy ? g_buy.isClosing   : g_sell.isClosing;
   bool isHedging   = isBuy ? g_buy.isHedging   : g_sell.isHedging;
   if(!initialized) return;
   if(isClosing || isHedging) return;

   int positionCount = CountPositions(isBuy);
   if(positionCount==0) return; // 无仓则等待重建

   double lastHedgePrice = isBuy ? g_buy.lastHedgePrice : g_sell.lastHedgePrice;
   int hedgeLevel = isBuy ? g_buy.hedgeLevel : g_sell.hedgeLevel;
   datetime lastTradeTime = isBuy ? g_buy.lastTradeTime : g_sell.lastTradeTime;
   double nextHedgeLot = isBuy ? g_buy.nextHedgeLot : g_sell.nextHedgeLot;

   double currentPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double priceDiffPoints = isBuy ? (lastHedgePrice - currentPrice)/_Point
                                  : (currentPrice - lastHedgePrice)/_Point;
   double priceDiffUSD = priceDiffPoints * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) * InitialLot;

   double hedgeThresholdUSD = 2.0;
   if(hedgeLevel==1) hedgeThresholdUSD = 3.0;
   else if(hedgeLevel==2) hedgeThresholdUSD = 5.0;
   else if(hedgeLevel>=3) hedgeThresholdUSD = 10.0;

   // 节流打印
   static datetime lastDbg=0;
   if(TimeCurrent()-lastDbg>=10)
   {
      PrintFormat("%s侧加仓检查: 价=%.3f 基准=%.3f 差=%.2fUSD 需=%.2fUSD 次=%d",
                  isBuy?"多":"空", currentPrice, lastHedgePrice, priceDiffUSD, hedgeThresholdUSD, hedgeLevel);
      lastDbg = TimeCurrent();
   }

   if(priceDiffUSD < hedgeThresholdUSD) return;
   if(hedgeLevel >= MaxHedgeLevel) return;
   if(TimeCurrent() - lastTradeTime < MinHedgeIntervalSec) return;

   if(isBuy) g_buy.isHedging = true; else g_sell.isHedging = true;
   double lotSize = nextHedgeLot;

   PrintFormat("📈 %s侧执行第%d次加仓 手数=%.2f", isBuy?"多":"空", hedgeLevel+1, lotSize);

   if(OpenOrder(isBuy, lotSize, "Hedge "+IntegerToString(hedgeLevel+1)))
   {
      if(isBuy)
      {
         g_buy.hedgeLevel++;
         g_buy.nextHedgeLot = CalcNextHedgeLot(g_buy.nextHedgeLot);
         g_buy.lastHedgePrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         g_buy.lastTradeTime = TimeCurrent();
         PrintFormat("✅ %s侧加仓成功 新基准价=%.3f", "多", g_buy.lastHedgePrice);
      }
      else
      {
         g_sell.hedgeLevel++;
         g_sell.nextHedgeLot = CalcNextHedgeLot(g_sell.nextHedgeLot);
         g_sell.lastHedgePrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         g_sell.lastTradeTime = TimeCurrent();
         PrintFormat("✅ %s侧加仓成功 新基准价=%.3f", "空", g_sell.lastHedgePrice);
      }
   }

   if(isBuy) g_buy.isHedging = false; else g_sell.isHedging = false;
}

//+------------------------------------------------------------------+
double CalcNextHedgeLot(double currentLot)
{
   double newLot = 0;
   if(currentLot < 0.16)
      newLot = currentLot * 2.0;
   else
      newLot = currentLot * 1.2;
   return NormalizeDouble(newLot, 2);
}

//+------------------------------------------------------------------+
int CountPositions(bool isBuy)
{
   int count=0;
   long targetType = isBuy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   long targetMagic = isBuy ? MagicNumberBuy : MagicNumberSell;
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

//+------------------------------------------------------------------+
double CalculateProfit(bool isBuy)
{
   double profit=0;
   long targetType = isBuy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   long targetMagic = isBuy ? MagicNumberBuy : MagicNumberSell;
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

//+------------------------------------------------------------------+
bool OpenOrder(bool isBuy, double lot, string comment)
{
   if(!g_isAuthorized)
   {
      Print("❌ 未授权，无法执行交易");
      return false;
   }
   
   MqlTradeRequest req={};
   MqlTradeResult  res={};

   req.action = TRADE_ACTION_DEAL;
   req.symbol = _Symbol;
   req.volume = lot;
   req.deviation = MaxSlippage;
   req.magic = isBuy ? MagicNumberBuy : MagicNumberSell;
   req.comment = comment;

   if(isBuy)
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
      PrintFormat("✅ 下单成功 %s 手数=%.2f 价=%.3f", comment, lot, res.price);
      return true;
   }
   else
   {
      PrintFormat("❌ 下单失败 %s err=%d", comment, GetLastError());
      return false;
   }
}

//+------------------------------------------------------------------+
void CloseAll(bool isBuy)
{
   long targetType = isBuy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   long targetMagic = isBuy ? MagicNumberBuy : MagicNumberSell;
   int closed=0;

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
               closed++;
         }
      }
   }
   PrintFormat("✅ 已平掉 %s侧 仓位数=%d", isBuy?"多":"空", closed);
}

//+------------------------------------------------------------------+


