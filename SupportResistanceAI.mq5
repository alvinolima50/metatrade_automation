#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//── parâmetros
input int    LookbackDays          = 10;
input int    MaxLinesPerGroup      = 4;
input color  DayColor              = clrDodgerBlue;
input color  WeekColor             = clrGold;
input color  PivotColor            = clrOrange;
input color  ADRColor              = clrSilver;
input ENUM_LINE_STYLE ADRStyle     = STYLE_DOT;
input int    ADR_Projection_Percent= 100;

#define FSR_PREFIX "FSR_"

double _pip;

//====================================================================
// INIT
//====================================================================
int OnInit()
{
   _pip = Point() * ((Digits()==3 || Digits()==5) ? 10.0 : 1.0);
   return(INIT_SUCCEEDED);
}

//====================================================================
// MAIN
//====================================================================
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

   DeleteMyObjects();

   // ---------------- High/Low dia atual & anterior -----------------
   datetime today   = DateOf(time[rates_total-1]);
   datetime prevday = today - 86400;

   double hiToday = -DBL_MAX, loToday = DBL_MAX;
   double hiPrev  = -DBL_MAX, loPrev  = DBL_MAX;
   double closePrev = 0;   // último fechamento do dia anterior

   for(int i=rates_total-1; i>=0; i--)
   {
      datetime d = DateOf(time[i]);

      if(d == today)
      {
         hiToday = MathMax(hiToday, high[i]);
         loToday = MathMin(loToday, low[i]);
      }
      else if(d == prevday)
      {
         hiPrev  = MathMax(hiPrev,  high[i]);
         loPrev  = MathMin(loPrev,  low[i]);
         if(closePrev == 0)       // pega o 1º (que é o último candle do loop)
            closePrev = close[i];
      }
      else if(d < prevday) break; // já passamos dos dois dias
   }

   DrawHL("HiPrev" , hiPrev , DayColor);
   DrawHL("LoPrev" , loPrev , DayColor);
   DrawHL("HiToday", hiToday, DayColor, STYLE_DASH);
   DrawHL("LoToday", loToday, DayColor, STYLE_DASH);

   // ---------------- High/Low semana atual & anterior --------------
   datetime monday   = WeekStart(today);
   datetime prevMon  = monday - 7*86400;

   double hiWeek = -DBL_MAX, loWeek = DBL_MAX;
   double hiPrevW= -DBL_MAX, loPrevW= DBL_MAX;

   for(int i=rates_total-1; i>=0; i--)
   {
      datetime d = DateOf(time[i]);
      if(d >= monday)               { hiWeek  = MathMax(hiWeek , high[i]); loWeek  = MathMin(loWeek , low[i]); }
      else if(d >= prevMon && d<monday)
                                     { hiPrevW = MathMax(hiPrevW, high[i]); loPrevW = MathMin(loPrevW, low[i]); }
      else if(d < prevMon) break;
   }

   DrawHL("HiWeekPrev", hiPrevW, WeekColor);
   DrawHL("LoWeekPrev", loPrevW, WeekColor);
   DrawHL("HiWeek"    , hiWeek , WeekColor, STYLE_DASH);
   DrawHL("LoWeek"    , loWeek , WeekColor, STYLE_DASH);

   // ---------------- Pivôs de piso (dia anterior) ------------------
   if(closePrev != 0)   // apenas se encontramos o close do dia anterior
   {
      double PP = (hiPrev + loPrev + closePrev) / 3.0;
      double R1 = 2*PP - loPrev;
      double S1 = 2*PP - hiPrev;
      double R2 = PP + (hiPrev - loPrev);
      double S2 = PP - (hiPrev - loPrev);

      DrawHL("PP", PP, PivotColor, STYLE_SOLID, 2);
      DrawHL("R1", R1, PivotColor);
      DrawHL("S1", S1, PivotColor);
      DrawHL("R2", R2, PivotColor);
      DrawHL("S2", S2, PivotColor);
   }

   // ---------------- ADR (Average Daily Range) ---------------------
   double adr = 0; int days = 0;
   datetime curDay = today;
   double dHi=-DBL_MAX, dLo=DBL_MAX;

   for(int i=rates_total-1; i>=0 && days<LookbackDays; i--)
   {
      datetime d = DateOf(time[i]);
      if(d != curDay)
      {
         adr += dHi - dLo;
         days++;
         curDay = d;
         dHi = -DBL_MAX; dLo = DBL_MAX;
      }
      dHi = MathMax(dHi, high[i]);
      dLo = MathMin(dLo, low[i]);
   }
   if(days > 0)
   {
      adr /= days;
      double projUp  = close[rates_total-1] + adr * ADR_Projection_Percent / 100.0;
      double projDwn = close[rates_total-1] - adr * ADR_Projection_Percent / 100.0;

      DrawHL("ADR_UP",  projUp , ADRColor, ADRStyle);
      DrawHL("ADR_DN",  projDwn, ADRColor, ADRStyle);
   }

   return(rates_total);
}

//====================================================================
//  UTILIDADES
//====================================================================
void DrawHL(string tag,double price,color clr,
            ENUM_LINE_STYLE style=STYLE_SOLID,int width=1)
{
   if(price<=0 || price==EMPTY_VALUE) return;
   string name = FSR_PREFIX + tag;
   ObjectCreate(0,name,OBJ_HLINE,0,0,price);
   ObjectSetInteger(0,name,OBJPROP_COLOR, clr);
   ObjectSetInteger(0,name,OBJPROP_STYLE, style);
   ObjectSetInteger(0,name,OBJPROP_WIDTH, width);
}

void DeleteMyObjects()
{
   for(int i=ObjectsTotal(0)-1; i>=0; i--)
      if(StringFind(ObjectName(0,i), FSR_PREFIX) == 0)
         ObjectDelete(0, ObjectName(0,i));
}

datetime DateOf(datetime t){ MqlDateTime dt; TimeToStruct(t,dt); return(t - dt.hour*3600 - dt.min*60 - dt.sec); }

datetime WeekStart(datetime d)
{
   MqlDateTime dt; TimeToStruct(d,dt);
   int w = dt.day_of_week==0 ? 6 : dt.day_of_week-1;
   return(d - w*86400 - dt.hour*3600 - dt.min*60 - dt.sec);
}
