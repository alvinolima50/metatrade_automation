//+------------------------------------------------------------------+
//|                                                 SR_Indicator.mq5 |
//|                                      Indicador de Suporte e Resistência |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_buffers 6     // Reduzido para 6 buffers
#property indicator_plots   0     // Mantemos 0 pois usamos objetos gráficos personalizados

//── Parâmetros
input datetime StartDate           = D'2025.03.01 00:00';  // Data inicial para análise
input datetime EndDate             = D'2025.05.10 00:00';  // Data final para análise
input int    HistoricalDays        = 70;        // Dias para análise histórica
input int    H4_Lookback           = 400;       // Barras para análise H4
input int    H1_Lookback           = 600;       // Barras para análise H1
input int    RecentDaysMarket      = 5;         // Dias recentes (abertura/fechamento)
input int    MaxH4Lines            = 8;         // Número máximo de linhas H4
input int    MaxH1Lines            = 10;        // Número máximo de linhas H1
input double ZoneThreshold         = 0.0008;    // Limiar para zonas de consolidação
input double TouchesForStrong      = 2;         // Número de toques para considerar forte
input color  H4_StrongColor        = clrCrimson;  // Cor para SR forte em H4
input color  H1_StrongColor        = clrGold;     // Cor para SR forte em H1
input color  MarketHoursColor      = clrDodgerBlue; // Cor para linhas de mercado
input int    LineWidth_H4          = 2;         // Largura das linhas H4
input int    LineWidth_H1          = 1;         // Largura das linhas H1
input int    LineWidth_Market      = 1;         // Largura das linhas de mercado
input ENUM_LINE_STYLE StyleH4      = STYLE_SOLID;    // Estilo das linhas H4
input ENUM_LINE_STYLE StyleH1      = STYLE_SOLID;    // Estilo das linhas H1
input ENUM_LINE_STYLE StyleMarket  = STYLE_DASH;     // Estilo das linhas de mercado

#define PREFIX "SR_"

// Arrays para armazenar os níveis de suporte e resistência em buffers
double H4_Support_Resistance[];   // Buffer 0 - Níveis de suporte e resistência H4
double H1_Support_Resistance[];   // Buffer 1 - Níveis de suporte e resistência H1
double MarketOpenBuffer[];        // Buffer 2 - Níveis de abertura do mercado
double MarketCloseBuffer[];       // Buffer 3 - Níveis de fechamento do mercado
double MarketHighBuffer[];        // Buffer 4 - Níveis de máximas do mercado
double MarketLowBuffer[];         // Buffer 5 - Níveis de mínimas do mercado

// Buffer adicional para distinguir suporte de resistência
double H4_SR_Type[];              // 1.0 = Suporte, 2.0 = Resistência
double H1_SR_Type[];              // 1.0 = Suporte, 2.0 = Resistência

double _pip;
int handle_H4, handle_H1;
int rates_total_global;

// Contador para quantos níveis foram encontrados em cada buffer
int h4SRCount = 0;
int h1SRCount = 0;
int marketCount = 0;

//+------------------------------------------------------------------+
//| Estrutura para armazenar níveis de suporte e resistência         |
//+------------------------------------------------------------------+
struct SRLevel
{
   double price;
   int touches;
   bool isResistance;
};

//+------------------------------------------------------------------+
//| Custom indicator initialization function                          |
//+------------------------------------------------------------------+
int OnInit()
{
   _pip = Point() * ((Digits()==3 || Digits()==5) ? 10.0 : 1.0);
   
   // Configurar buffers do indicador - isso permite acesso via MT5 Python API
   SetIndexBuffer(0, H4_Support_Resistance, INDICATOR_DATA);
   SetIndexBuffer(1, H1_Support_Resistance, INDICATOR_DATA);
   SetIndexBuffer(2, MarketOpenBuffer, INDICATOR_DATA);
   SetIndexBuffer(3, MarketCloseBuffer, INDICATOR_DATA);
   SetIndexBuffer(4, MarketHighBuffer, INDICATOR_DATA);
   SetIndexBuffer(5, MarketLowBuffer, INDICATOR_DATA);
   
   // Buffers auxiliares para tipos (não expostos, apenas para uso interno)
   ArrayResize(H4_SR_Type, 1000);
   ArrayResize(H1_SR_Type, 1000);
   
   // Definir nomes para os buffers para facilitar o acesso via Python
   PlotIndexSetString(0, PLOT_LABEL, "H4_Support_Resistance");
   PlotIndexSetString(1, PLOT_LABEL, "H1_Support_Resistance");
   PlotIndexSetString(2, PLOT_LABEL, "Market_Open");
   PlotIndexSetString(3, PLOT_LABEL, "Market_Close");
   PlotIndexSetString(4, PLOT_LABEL, "Market_High");
   PlotIndexSetString(5, PLOT_LABEL, "Market_Low");
   
   // Inicializar contadores
   h4SRCount = 0;
   h1SRCount = 0;
   marketCount = 0;
   
   // Inicializar os arrays com EMPTY_VALUE
   ArrayInitialize(H4_Support_Resistance, EMPTY_VALUE);
   ArrayInitialize(H1_Support_Resistance, EMPTY_VALUE);
   ArrayInitialize(MarketOpenBuffer, EMPTY_VALUE);
   ArrayInitialize(MarketCloseBuffer, EMPTY_VALUE);
   ArrayInitialize(MarketHighBuffer, EMPTY_VALUE);
   ArrayInitialize(MarketLowBuffer, EMPTY_VALUE);
   ArrayInitialize(H4_SR_Type, 0);
   ArrayInitialize(H1_SR_Type, 0);
   
   // Abrir handles para timeframes H4 e H1
   handle_H4 = iOpen(Symbol(), PERIOD_H4, 0);
   handle_H1 = iOpen(Symbol(), PERIOD_H1, 0);
   
   if(handle_H4 == INVALID_HANDLE || handle_H1 == INVALID_HANDLE)
   {
      Print("Erro ao abrir handles para timeframes: ", GetLastError());
      return(INIT_FAILED);
   }
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                        |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   DeleteAllLines();
   
   // Fechar handles
   if(handle_H4 != INVALID_HANDLE) IndicatorRelease(handle_H4);
   if(handle_H1 != INVALID_HANDLE) IndicatorRelease(handle_H1);
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                               |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double  &open[],
                const double  &high[],
                const double  &low[],
                const double  &close[],
                const long    &tick_vol[],
                const long    &vol[],
                const int     &spread[])
{
   if(rates_total < 2) return(rates_total);

   // Armazenar rates_total para uso em outras funções
   rates_total_global = rates_total;
   
   // Limpar buffers e linhas existentes
   DeleteAllLines();
   
   // Resetar contadores
   h4SRCount = 0;
   h1SRCount = 0;
   marketCount = 0;
   
   // Inicializar buffers com EMPTY_VALUE
   ArrayInitialize(H4_Support_Resistance, EMPTY_VALUE);
   ArrayInitialize(H1_Support_Resistance, EMPTY_VALUE);
   ArrayInitialize(MarketOpenBuffer, EMPTY_VALUE);
   ArrayInitialize(MarketCloseBuffer, EMPTY_VALUE);
   ArrayInitialize(MarketHighBuffer, EMPTY_VALUE);
   ArrayInitialize(MarketLowBuffer, EMPTY_VALUE);
   ArrayInitialize(H4_SR_Type, 0);
   ArrayInitialize(H1_SR_Type, 0);
   
   // Adicionar comentário com informações do período analisado
   string info = "Análise SR: " + TimeToString(StartDate, TIME_DATE) + " a " + 
                TimeToString(EndDate, TIME_DATE);
   Comment(info);

   // Encontrar níveis de suporte e resistência para H4
   FindAndDrawSR(PERIOD_H4, H4_Lookback, MaxH4Lines, H4_StrongColor, StyleH4, LineWidth_H4);
   
   // Encontrar níveis de suporte e resistência para H1
   FindAndDrawSR(PERIOD_H1, H1_Lookback, MaxH1Lines, H1_StrongColor, StyleH1, LineWidth_H1);
   
   // Desenhar linhas de abertura e fechamento do mercado dos últimos dias
   DrawMarketOpenClose(RecentDaysMarket, MarketHoursColor, StyleMarket, LineWidth_Market);
   
   // Exportar os dados para JSON para facilitar o debug e a integração
   ExportSRLevelsToJSON();
   
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Encontrar e desenhar níveis de suporte e resistência             |
//+------------------------------------------------------------------+
void FindAndDrawSR(ENUM_TIMEFRAMES timeframe, int lookback, int maxLines, 
                  color lineColor, ENUM_LINE_STYLE lineStyle, int lineWidth)
{
   int handle = (timeframe == PERIOD_H4) ? handle_H4 : handle_H1;
   string prefix = (timeframe == PERIOD_H4) ? "H4_" : "H1_";
   
   // Arrays para armazenar dados
   double high[], low[], close[], open[];
   datetime time[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(time, true);
   
   // Obter dados históricos com base no intervalo de datas
   int copied = CopyTime(Symbol(), timeframe, 0, lookback, time);
   if(copied <= 0) return;
   
   copied = CopyHigh(Symbol(), timeframe, 0, lookback, high);
   if(copied <= 0) return;
   
   copied = CopyLow(Symbol(), timeframe, 0, lookback, low);
   if(copied <= 0) return;
   
   copied = CopyClose(Symbol(), timeframe, 0, lookback, close);
   if(copied <= 0) return;
   
   copied = CopyOpen(Symbol(), timeframe, 0, lookback, open);
   if(copied <= 0) return;
   
   // Extrair potenciais níveis de suporte e resistência
   SRLevel levels[];
   int levelsCount = 0;
   
   // Encontrar o índice correspondente às datas de início e fim
   int startIdx = -1, endIdx = -1;
   for(int i = 0; i < copied; i++) {
      if(time[i] <= EndDate && endIdx == -1) endIdx = i;
      if(time[i] <= StartDate) { startIdx = i; break; }
   }
   
   if(startIdx == -1) startIdx = copied - 1;
   if(endIdx == -1) endIdx = 0;
   
   // Procurar por swing highs e lows no intervalo de datas específico
   for(int i = endIdx + 2; i < startIdx - 2; i++)
   {
      // Swing high - mais rigoroso
      if(IsSwingHighEnhanced(high, i, 3))
      {
         AddSRLevel(levels, levelsCount, high[i], true);
      }
      
      // Swing low - mais rigoroso
      if(IsSwingLowEnhanced(low, i, 3))
      {
         AddSRLevel(levels, levelsCount, low[i], false);
      }
   }
   
   // Adicionar níveis de preço de abertura/fechamento significativos
   for(int i = endIdx; i < startIdx; i++)
   {
      // Round numbers (níveis redondos) frequentemente servem como S/R
      double roundPrice = NormalizeDouble(close[i], 1);
      if(MathAbs(roundPrice - close[i]) < 0.05)
      {
         AddSRLevel(levels, levelsCount, roundPrice, close[i] < close[i+1]);
      }
   }
   
   // Contar toques em cada nível para todo o período
   CountTouchesEnhanced(levels, levelsCount, high, low, endIdx, startIdx, ZoneThreshold);
   
   // Classificar por número de toques
   SortLevelsByTouches(levels, levelsCount);
   
   // Desenhar apenas os níveis mais significativos
   int drawnCount = 0;
   
   for(int i = 0; i < levelsCount && drawnCount < maxLines; i++)
   {
      if(levels[i].touches >= TouchesForStrong)
      {
         string tag = prefix + (levels[i].isResistance ? "Resistance_" : "Support_") + IntegerToString(i);
         DrawHorizontalLine(tag, levels[i].price, lineColor, lineStyle, lineWidth);
         
         // Armazenar nos buffers para acesso via API
         if(timeframe == PERIOD_H4)
         {
            if(h4SRCount < rates_total_global)
            {
               H4_Support_Resistance[h4SRCount] = levels[i].price;
               H4_SR_Type[h4SRCount] = levels[i].isResistance ? 2.0 : 1.0; // 1.0 = Suporte, 2.0 = Resistência
               h4SRCount++;
            }
         }
         else if(timeframe == PERIOD_H1)
         {
            if(h1SRCount < rates_total_global)
            {
               H1_Support_Resistance[h1SRCount] = levels[i].price;
               H1_SR_Type[h1SRCount] = levels[i].isResistance ? 2.0 : 1.0; // 1.0 = Suporte, 2.0 = Resistência
               h1SRCount++;
            }
         }
         
         drawnCount++;
      }
   }
}

//+------------------------------------------------------------------+
//| Verifica se é um swing high                                      |
//+------------------------------------------------------------------+
bool IsSwingHigh(const double &high[], int index)
{
   return high[index] > high[index+1] && high[index] > high[index+2] && 
          high[index] > high[index-1] && high[index] > high[index-2];
}

//+------------------------------------------------------------------+
//| Verifica se é um swing high avançado (mais confirmações)         |
//+------------------------------------------------------------------+
bool IsSwingHighEnhanced(const double &high[], int index, int lookAround)
{
   if(lookAround < 2) lookAround = 2;
   
   bool isHigh = true;
   
   // Verificar candles à direita
   for(int i = 1; i <= lookAround && isHigh; i++)
      if(high[index] <= high[index+i]) isHigh = false;
      
   // Verificar candles à esquerda  
   for(int i = 1; i <= lookAround && isHigh; i++)
      if(high[index] <= high[index-i]) isHigh = false;
      
   return isHigh;
}

//+------------------------------------------------------------------+
//| Verifica se é um swing low                                       |
//+------------------------------------------------------------------+
bool IsSwingLow(const double &low[], int index)
{
   return low[index] < low[index+1] && low[index] < low[index+2] && 
          low[index] < low[index-1] && low[index] < low[index-2];
}

//+------------------------------------------------------------------+
//| Verifica se é um swing low avançado (mais confirmações)          |
//+------------------------------------------------------------------+
bool IsSwingLowEnhanced(const double &low[], int index, int lookAround)
{
   if(lookAround < 2) lookAround = 2;
   
   bool isLow = true;
   
   // Verificar candles à direita
   for(int i = 1; i <= lookAround && isLow; i++)
      if(low[index] >= low[index+i]) isLow = false;
      
   // Verificar candles à esquerda  
   for(int i = 1; i <= lookAround && isLow; i++)
      if(low[index] >= low[index-i]) isLow = false;
      
   return isLow;
}

//+------------------------------------------------------------------+
//| Adiciona um nível de suporte ou resistência                      |
//+------------------------------------------------------------------+
void AddSRLevel(SRLevel &levels[], int &count, double price, bool isResistance)
{
   // Verificar se já existe um nível próximo
   for(int i = 0; i < count; i++)
   {
      if(MathAbs(levels[i].price - price) < ZoneThreshold)
      {
         // Atualizar nível existente com média
         levels[i].price = (levels[i].price + price) / 2.0;
         return;
      }
   }
   
   // Ignorar níveis muito extremos (fora da faixa relevante do gráfico)
   double currentPrice = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double priceRange = MathAbs(currentPrice) * 0.15; // 15% do preço atual
   
   if(MathAbs(price - currentPrice) > priceRange)
      return;
      
   // Adicionar novo nível
   ArrayResize(levels, count + 1);
   levels[count].price = price;
   levels[count].touches = 1;
   levels[count].isResistance = isResistance;
   count++;
}

//+------------------------------------------------------------------+
//| Conta toques em cada nível                                       |
//+------------------------------------------------------------------+
void CountTouches(SRLevel &levels[], int count, const double &high[], const double &low[], 
                 int lookback, double threshold)
{
   for(int i = 0; i < count; i++)
   {
      levels[i].touches = 0;
      
      for(int j = 0; j < lookback; j++)
      {
         // Verificar se o preço alto tocou no nível de resistência
         if(levels[i].isResistance && MathAbs(high[j] - levels[i].price) < threshold)
         {
            levels[i].touches++;
         }
         
         // Verificar se o preço baixo tocou no nível de suporte
         if(!levels[i].isResistance && MathAbs(low[j] - levels[i].price) < threshold)
         {
            levels[i].touches++;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Conta toques em cada nível com detecção avançada                 |
//+------------------------------------------------------------------+
void CountTouchesEnhanced(SRLevel &levels[], int count, const double &high[], const double &low[], 
                        int startIndex, int endIndex, double threshold)
{
   for(int i = 0; i < count; i++)
   {
      levels[i].touches = 0;
      int consecutiveCount = 0;
      bool lastWasTouch = false;
      
      for(int j = startIndex; j <= endIndex; j++)
      {
         bool isTouching = false;
         
         // Verificar se o preço alto tocou ou se aproximou do nível de resistência
         if(levels[i].isResistance && MathAbs(high[j] - levels[i].price) < threshold)
         {
            isTouching = true;
         }
         
         // Verificar se o preço baixo tocou ou se aproximou do nível de suporte
         if(!levels[i].isResistance && MathAbs(low[j] - levels[i].price) < threshold)
         {
            isTouching = true;
         }
         
         // Contar toques considerando apenas mudanças (não toques consecutivos)
         if(isTouching)
         {
            if(!lastWasTouch)
            {
               levels[i].touches++;
               lastWasTouch = true;
            }
            consecutiveCount++;
         }
         else
         {
            lastWasTouch = false;
            consecutiveCount = 0;
         }
         
         // Aumentar a relevância para toques múltiplos consecutivos
         if(consecutiveCount >= 3)
         {
            levels[i].touches++; // Mais peso para níveis que têm resistência persistente
            consecutiveCount = 0;
         }
      }
      
      // Verificar também uma rejeição clara (toques seguidos de reversão)
      for(int j = startIndex + 1; j < endIndex; j++)
      {
         // Verificar se houve uma rejeição significativa em um nível de resistência
         if(levels[i].isResistance && 
            MathAbs(high[j] - levels[i].price) < threshold &&
            high[j+1] < high[j] - threshold*3 &&
            high[j-1] < high[j] - threshold*3)
         {
            levels[i].touches += 2; // Rejeição clara tem mais peso
         }
         
         // Verificar se houve uma rejeição significativa em um nível de suporte
         if(!levels[i].isResistance && 
            MathAbs(low[j] - levels[i].price) < threshold &&
            low[j+1] > low[j] + threshold*3 &&
            low[j-1] > low[j] + threshold*3)
         {
            levels[i].touches += 2; // Rejeição clara tem mais peso
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Ordena níveis pelo número de toques                              |
//+------------------------------------------------------------------+
void SortLevelsByTouches(SRLevel &levels[], int count)
{
   for(int i = 0; i < count - 1; i++)
   {
      for(int j = i + 1; j < count; j++)
      {
         if(levels[j].touches > levels[i].touches)
         {
            SRLevel temp = levels[i];
            levels[i] = levels[j];
            levels[j] = temp;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Desenha linhas de abertura e fechamento do mercado               |
//+------------------------------------------------------------------+
void DrawMarketOpenClose(int days, color lineColor, ENUM_LINE_STYLE lineStyle, int lineWidth)
{
   datetime time[];
   double open[], close[], high[], low[];
   
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   
   // Encontrar o índice correspondente ao período entre StartDate e EndDate
   int startIdx = iBarShift(Symbol(), PERIOD_D1, StartDate, false);
   int endIdx = iBarShift(Symbol(), PERIOD_D1, EndDate, false);
   
   if(startIdx < 0 || endIdx < 0) {
      // Se não conseguir encontrar índices exatos, buscar os últimos "days" dias
      int copied = CopyTime(Symbol(), PERIOD_D1, 0, days + 1, time);
      if(copied <= 0) return;
      
      copied = CopyOpen(Symbol(), PERIOD_D1, 0, days + 1, open);
      if(copied <= 0) return;
      
      copied = CopyClose(Symbol(), PERIOD_D1, 0, days + 1, close);
      if(copied <= 0) return;
      
      copied = CopyHigh(Symbol(), PERIOD_D1, 0, days + 1, high);
      if(copied <= 0) return;
      
      copied = CopyLow(Symbol(), PERIOD_D1, 0, days + 1, low);
      if(copied <= 0) return;
      
      // Desenhar linhas de abertura e fechamento para os últimos dias
      for(int i = 0; i < days && i < copied - 1; i++)
      {
         string openTag = "Market_Open_" + TimeToString(time[i], TIME_DATE);
         string closeTag = "Market_Close_" + TimeToString(time[i+1], TIME_DATE);
         string highTag = "Market_High_" + TimeToString(time[i], TIME_DATE);
         string lowTag = "Market_Low_" + TimeToString(time[i], TIME_DATE);
         
         DrawHorizontalLine(openTag, open[i], lineColor, lineStyle, lineWidth);
         DrawHorizontalLine(closeTag, close[i+1], lineColor, lineStyle, lineWidth);
         DrawHorizontalLine(highTag, high[i], lineColor, STYLE_DOT, 1);
         DrawHorizontalLine(lowTag, low[i], lineColor, STYLE_DOT, 1);
         
         // Armazenar valores nos buffers
         if(marketCount < rates_total_global)
         {
            MarketOpenBuffer[marketCount] = open[i];
            MarketCloseBuffer[marketCount] = close[i+1];
            MarketHighBuffer[marketCount] = high[i];
            MarketLowBuffer[marketCount] = low[i];
            marketCount++;
         }
      }
   } else {
      // Usar o intervalo de datas selecionado
      int totalDays = startIdx - endIdx + 1;
      days = MathMin(days, totalDays);
      
      // Copiar dados para o intervalo específico
      int copied = CopyTime(Symbol(), PERIOD_D1, endIdx, days, time);
      if(copied <= 0) return;
      
      copied = CopyOpen(Symbol(), PERIOD_D1, endIdx, days, open);
      if(copied <= 0) return;
      
      copied = CopyClose(Symbol(), PERIOD_D1, endIdx, days, close);
      if(copied <= 0) return;
      
      copied = CopyHigh(Symbol(), PERIOD_D1, endIdx, days, high);
      if(copied <= 0) return;
      
      copied = CopyLow(Symbol(), PERIOD_D1, endIdx, days, low);
      if(copied <= 0) return;
      
      // Desenhar linhas de abertura e fechamento para os dias selecionados
      for(int i = 0; i < copied; i++)
      {
         string openTag = "Market_Open_" + TimeToString(time[i], TIME_DATE);
         string closeTag = "Market_Close_" + TimeToString(time[i], TIME_DATE);
         string highTag = "Market_High_" + TimeToString(time[i], TIME_DATE);
         string lowTag = "Market_Low_" + TimeToString(time[i], TIME_DATE);
         
         DrawHorizontalLine(openTag, open[i], lineColor, lineStyle, lineWidth);
         DrawHorizontalLine(closeTag, close[i], lineColor, lineStyle, lineWidth);
         DrawHorizontalLine(highTag, high[i], lineColor, STYLE_DOT, 1);
         DrawHorizontalLine(lowTag, low[i], lineColor, STYLE_DOT, 1);
         
         // Armazenar valores nos buffers
         if(marketCount < rates_total_global)
         {
            MarketOpenBuffer[marketCount] = open[i];
            MarketCloseBuffer[marketCount] = close[i];
            MarketHighBuffer[marketCount] = high[i];
            MarketLowBuffer[marketCount] = low[i];
            marketCount++;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Desenha uma linha horizontal                                     |
//+------------------------------------------------------------------+
void DrawHorizontalLine(string tag, double price, color clr, 
                       ENUM_LINE_STYLE style, int width)
{
   if(price <= 0 || price == EMPTY_VALUE) return;
   
   string name = PREFIX + tag;
   ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, tag + ": " + DoubleToString(price, Digits()));
}

//+------------------------------------------------------------------+
//| Remove todas as linhas criadas pelo indicador                    |
//+------------------------------------------------------------------+
void DeleteAllLines()
{
   for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i);
      if(StringFind(name, PREFIX) == 0)
      {
         ObjectDelete(0, name);
      }
   }
}

//+------------------------------------------------------------------+
//| Exporta os níveis de SR para um arquivo JSON                     |
//+------------------------------------------------------------------+
void ExportSRLevelsToJSON()
{
   string filename = "SR_Levels_" + Symbol() + ".json";
   int fileHandle = FileOpen(filename, FILE_WRITE|FILE_TXT|FILE_ANSI);
   
   if(fileHandle != INVALID_HANDLE)
   {
      string json = "{\n";
      
      // H4 Support e Resistance (agora combinados)
      json += "  \"H4_Support_Resistance\": [\n";
      for(int i = 0; i < h4SRCount; i++)
      {
         if(i > 0) json += ",\n";
         json += "    {";
         json += "\"price\": " + DoubleToString(H4_Support_Resistance[i], Digits()) + ", ";
         json += "\"type\": \"" + (H4_SR_Type[i] == 1.0 ? "Support" : "Resistance") + "\"";
         json += "}";
      }
      json += "\n  ],\n";
      
      // H1 Support e Resistance (agora combinados)
      // H1 Support e Resistance (agora combinados)
      json += "  \"H1_Support_Resistance\": [\n";
      for(int i = 0; i < h1SRCount; i++)
      {
         if(i > 0) json += ",\n";
         json += "    {";
         json += "\"price\": " + DoubleToString(H1_Support_Resistance[i], Digits()) + ", ";
         json += "\"type\": \"" + (H1_SR_Type[i] == 1.0 ? "Support" : "Resistance") + "\"";
         json += "}";
      }
      json += "\n  ],\n";
      
      // Market Data
      json += "  \"Market_Data\": [\n";
      for(int i = 0; i < marketCount; i++)
      {
         if(i > 0) json += ",\n";
         json += "    {";
         json += "\"open\": " + DoubleToString(MarketOpenBuffer[i], Digits()) + ", ";
         json += "\"close\": " + DoubleToString(MarketCloseBuffer[i], Digits()) + ", ";
         json += "\"high\": " + DoubleToString(MarketHighBuffer[i], Digits()) + ", ";
         json += "\"low\": " + DoubleToString(MarketLowBuffer[i], Digits());
         json += "}";
      }
      json += "\n  ]\n";
      
      json += "}";
      
      FileWriteString(fileHandle, json);
      FileClose(fileHandle);
      
      Print("Níveis de SR exportados para: " + filename);
   }
   else
   {
      Print("Erro ao abrir arquivo para exportação: ", GetLastError());
   }
}      