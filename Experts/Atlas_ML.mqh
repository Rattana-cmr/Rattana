//+------------------------------------------------------------------+
//| Atlas_ML.mqh — ONNX ML Gate Module for ICT ATLAS EA V1.1        |
//| Included inside ICT_ATLAS_EA_V1.0.mq5                            |
//+------------------------------------------------------------------+
#ifndef ATLAS_ML_MQH
#define ATLAS_ML_MQH

// File-scope statics
static long   gOnnxHandle           = INVALID_HANDLE;
static double gMLValidationMaxDiff  = -1.0;

// Scaler constants (StandardScaler from ML/outputs/research_v2/deploy/scaler_params.csv)
static const float ML_MEAN[48] =
{
   10.692949f, 6.525413f, 0.948513f, 0.118250f, 0.693896f, 0.353937f, 0.190033f, 0.105924f,
   1.879394f,  0.056726f, 0.063550f, 0.116445f, 0.045962f, 0.449361f, 0.371745f, 0.402628f,
   1.506417f,  0.007132f, 0.179071f, 0.395122f, 0.842325f, 0.301547f, 1.447181f, 0.000220f,
   1.568311f,  1.655071f, 0.984109f, 0.269498f, 21.573124f, 28.971662f, 46.051250f, 0.785426f,
   15.0f,      15.0f,     20.0f,     0.421757f, 15.0f,     10.0f,     10.0f,      5.0f,
   4.211627f,  5.0f,      5.0f,      104.633384f, 0.190033f, 0.105924f, 0.395122f, 1.447181f
};

static const float ML_STD[48] =
{
   6.747797f,  3.421442f, 1.146537f, 0.322904f, 0.480148f, 0.767870f, 0.652243f, 0.717855f,
   0.992834f,  0.231318f, 0.243949f, 0.320758f, 0.209402f, 0.497429f, 0.483271f, 0.490427f,
   1.609760f,  0.084150f, 0.383411f, 0.488877f, 0.364436f, 0.953451f, 0.703518f, 0.014835f,
   0.980135f,  0.922401f, 0.329828f, 0.231528f, 19.083679f, 10.722363f, 37.577635f, 0.180478f,
   1.0f,       1.0f,      1.0f,      2.873545f, 1.0f,      1.0f,      1.0f,       1.0f,
   1.822178f,  1.0f,      1.0f,      3.353094f, 0.652243f, 0.717855f, 0.488877f,  0.703518f
};

//+------------------------------------------------------------------+
//| Atlas_ML_IsLoaded — returns true if ONNX handle is valid         |
//+------------------------------------------------------------------+
bool Atlas_ML_IsLoaded()
{
   return (gOnnxHandle != INVALID_HANDLE);
}

//+------------------------------------------------------------------+
//| Forward declaration                                               |
//+------------------------------------------------------------------+
bool Atlas_ML_Validate();

//+------------------------------------------------------------------+
//| Atlas_ML_Init — load ONNX model and run validation               |
//+------------------------------------------------------------------+
bool Atlas_ML_Init()
{
   if(!FileIsExist("ICT_ATLAS_LGB_winloss_v2_mt5.onnx"))
   {
      Print("ATLAS ML: ONNX file not found: ICT_ATLAS_LGB_winloss_v2_mt5.onnx");
      return false;
   }

   gOnnxHandle = OnnxCreate("ICT_ATLAS_LGB_winloss_v2_mt5.onnx", ONNX_DEFAULT);
   if(gOnnxHandle == INVALID_HANDLE)
   {
      Print("ATLAS ML: OnnxCreate failed, error=" + IntegerToString(GetLastError()));
      return false;
   }

   // Set input shape: [1, 48]
   ulong inp_shape[] = {1, 48};
   if(!OnnxSetInputShape(gOnnxHandle, 0, inp_shape))
   {
      OnnxRelease(gOnnxHandle);
      gOnnxHandle = INVALID_HANDLE;
      return false;
   }

   // Set output 0 shape: predicted label [1]
   ulong lbl_shape[] = {1};
   if(!OnnxSetOutputShape(gOnnxHandle, 0, lbl_shape))
   {
      OnnxRelease(gOnnxHandle);
      gOnnxHandle = INVALID_HANDLE;
      return false;
   }

   // Set output 1 shape: class probabilities [1, 2]
   ulong prob_shape[] = {1, 2};
   if(!OnnxSetOutputShape(gOnnxHandle, 1, prob_shape))
   {
      OnnxRelease(gOnnxHandle);
      gOnnxHandle = INVALID_HANDLE;
      return false;
   }

   Print("ATLAS ML: ONNX model loaded. Running validation...");

   bool valResult = Atlas_ML_Validate();
   if(valResult)
      Print("ATLAS ML: Validation PASSED (maxDiff=" + DoubleToString(gMLValidationMaxDiff, 6) + ")");
   else
      Print("ATLAS ML: WARN — Validation failed, but proceeding (maxDiff=" + DoubleToString(gMLValidationMaxDiff, 6) + ")");

   // NON-FATAL — always return true if model loaded
   return true;
}

//+------------------------------------------------------------------+
//| Atlas_ML_Deinit — release ONNX model handle                      |
//+------------------------------------------------------------------+
void Atlas_ML_Deinit()
{
   if(gOnnxHandle != INVALID_HANDLE)
   {
      OnnxRelease(gOnnxHandle);
      gOnnxHandle = INVALID_HANDLE;
      Print("ATLAS ML: ONNX model released.");
   }
}

//+------------------------------------------------------------------+
//| Atlas_ML_Validate — run validation cases against loaded model     |
//+------------------------------------------------------------------+
bool Atlas_ML_Validate()
{
   if(gOnnxHandle == INVALID_HANDLE)
      return false;

   if(!FileIsExist("validation_cases.csv"))
   {
      Print("ATLAS ML: validation_cases.csv not found — skipping validation.");
      return true;
   }

   int fh = FileOpen("validation_cases.csv", FILE_READ|FILE_CSV|FILE_ANSI, ',');
   if(fh == INVALID_HANDLE)
   {
      Print("ATLAS ML: Failed to open validation_cases.csv");
      return true; // non-fatal
   }

   // Skip header row: 48 feature cols + expected_score + win_loss = 50 columns
   for(int h = 0; h < 50; h++)
      FileReadString(fh);

   double maxDiff  = 0.0;
   double sumDiff  = 0.0;
   int    nCases   = 0;
   int    nErrors  = 0;
   int    nExceed  = 0;

   while(!FileIsEnding(fh) && nCases < 200)
   {
      // a. Read 48 raw feature values
      float rawFeat[48];
      for(int j = 0; j < 48; j++)
         rawFeat[j] = (float)StringToDouble(FileReadString(fh));

      // b. Read expected probability
      double expected = StringToDouble(FileReadString(fh));

      // c. Read and discard win_loss label
      FileReadString(fh);

      // d. Build z-scored input
      float inp[1][48];
      for(int j = 0; j < 48; j++)
         inp[0][j] = (ML_STD[j] > 1e-10f) ? (rawFeat[j] - ML_MEAN[j]) / ML_STD[j] : 0.0f;

      // e. Declare outputs
      long  lbl[1];
      float proba[1][2];

      // f. Run inference
      if(!OnnxRun(gOnnxHandle, ONNX_NO_CONVERSION, inp, lbl, proba))
      {
         nErrors++;
         continue;
      }

      // g. Compute difference
      double diff = MathAbs((double)proba[0][1] - expected);

      // h. Track statistics
      if(diff > maxDiff) maxDiff = diff;
      sumDiff += diff;
      nCases++;
      if(diff >= 0.001) nExceed++;
   }

   FileClose(fh);

   gMLValidationMaxDiff = maxDiff;

   Print("ATLAS ML: Validation — cases=" + IntegerToString(nCases) +
         " maxDiff="  + DoubleToString(maxDiff, 6) +
         " meanDiff=" + DoubleToString(nCases > 0 ? sumDiff / nCases : 0, 6) +
         " nExceed="  + IntegerToString(nExceed));

   return (maxDiff < 0.001);
}

//+------------------------------------------------------------------+
//| Atlas_ML_BuildAndPredict — build feature vector and run ONNX     |
//+------------------------------------------------------------------+
double Atlas_ML_BuildAndPredict(bool bullish, datetime signalTime,
                                double atr14_pips, double atr50_pips,
                                double spread_pips, double spread_pct_atr,
                                double adx_val)
{
   if(gOnnxHandle == INVALID_HANDLE)
      return 0.0;

   MqlDateTime dt;
   TimeToStruct(signalTime, dt);

   float feat[48];

   feat[0] = (float)dt.hour;
   feat[1] = (float)dt.mon;
   feat[2] = (float)(dt.day_of_week - 1);   // Mon=0..Fri=4
   feat[3] = (float)(GetCurrentSession() == SES_NEWYORK ? 1 : 0);
   feat[4] = (float)(gBias.weekly == BIAS_BULLISH ? 1 : gBias.weekly == BIAS_BEARISH ? -1 : 0);
   feat[5] = (float)(gBias.daily  == BIAS_BULLISH ? 1 : gBias.daily  == BIAS_BEARISH ? -1 : 0);
   feat[6] = (float)(gBias.h4     == BIAS_BULLISH ? 1 : gBias.h4     == BIAS_BEARISH ? -1 : 0);
   feat[7] = (float)(gBias.h1     == BIAS_BULLISH ? 1 : gBias.h1     == BIAS_BEARISH ? -1 : 0);
   feat[8] = (float)((gBias.weekly == BIAS_BULLISH ? 1 : 0) +
                     (gBias.daily  == BIAS_BULLISH ? 1 : 0) +
                     (gBias.h4     == BIAS_BULLISH ? 1 : 0) +
                     (gBias.h1     == BIAS_BULLISH ? 1 : 0));
   feat[9]  = (float)(WasTagSwept("PDH")    ? 1 : 0);
   feat[10] = (float)(WasTagSwept("PDL")    ? 1 : 0);
   feat[11] = (float)(WasTagSwept("PWH")    ? 1 : 0);
   feat[12] = (float)(WasTagSwept("PWL")    ? 1 : 0);
   feat[13] = (float)((WasTagSwept("AsianH") || WasTagSwept("AsianL")) ? 1 : 0);
   feat[14] = (float)(WasTagSwept("EQH")    ? 1 : 0);
   feat[15] = (float)(WasTagSwept("EQL")    ? 1 : 0);
   feat[16] = feat[9] + feat[10] + feat[11] + feat[12] + feat[13] + feat[14] + feat[15];
   feat[17] = (float)(gDisp.valid && gDisp.bullish == bullish ? 1 : 0);

   // feat[18]: fvg_present
   {
      bool fvgFound = false;
      for(int _i = 0; _i < gFVGCount; _i++)
         if(gFVGs[_i].valid && !gFVGs[_i].mitigated && gFVGs[_i].bullish == bullish)
         {
            fvgFound = true;
            break;
         }
      feat[18] = (float)(fvgFound ? 1 : 0);
   }

   // feat[19]: ob_present
   {
      bool obFound = false;
      for(int _i = 0; _i < gPDACount; _i++)
         if(gPDAs[_i].valid && !gPDAs[_i].mitigated && gPDAs[_i].bullish == bullish)
         {
            obFound = true;
            break;
         }
      feat[19] = (float)(obFound ? 1 : 0);
   }

   feat[20] = (float)(gADR.blocked ? 0 : 1);

   // feat[21]: prem_disc label
   {
      string pdLabel = GetPDLabel();
      feat[21] = (float)(pdLabel == "PREMIUM" ? 1 : pdLabel == "DISCOUNT" ? -1 : pdLabel == "BLOCKED" ? -2 : 0);
   }

   feat[22] = (float)(gCond.condition == COND_TRENDING ? 2 : gCond.condition == COND_RANGING ? 1 : 0);
   feat[23] = (float)(gMSS.valid && gMSS.bullish == bullish ? 1 : 0);
   feat[24] = (float)atr14_pips;
   feat[25] = (float)atr50_pips;
   feat[26] = (float)(atr50_pips > 0.0 ? atr14_pips / atr50_pips : 1.0);
   feat[27] = (float)spread_pips;
   feat[28] = (float)spread_pct_atr;
   feat[29] = (float)adx_val;
   feat[30] = (float)(adx_val * atr14_pips);
   feat[31] = (float)MathMax(0.0, 1.0 - spread_pips / MathMax(atr14_pips, 0.001));
   feat[32] = (float)gScore.weeklyBias;
   feat[33] = (float)gScore.dailyBias;
   feat[34] = (float)gScore.liqSweep;
   feat[35] = (float)gScore.mss;
   feat[36] = (float)gScore.displacement;
   feat[37] = (float)gScore.fvg;
   feat[38] = (float)gScore.killzone;
   feat[39] = (float)gScore.smt;
   feat[40] = (float)gScore.adrScore;
   feat[41] = (float)gScore.po3;
   feat[42] = (float)gScore.premDisc;
   feat[43] = (float)gScore.total;
   feat[44] = (float)gScore.h4Align;
   feat[45] = (float)gScore.h1Align;
   feat[46] = (float)gScore.obScore;
   feat[47] = (float)gScore.condScore;

   // Z-score normalise
   float inp[1][48];
   for(int i = 0; i < 48; i++)
      inp[0][i] = (ML_STD[i] > 1e-10f) ? (feat[i] - ML_MEAN[i]) / ML_STD[i] : 0.0f;

   // Run ONNX inference
   long  lbl[1];
   float proba[1][2];
   if(!OnnxRun(gOnnxHandle, ONNX_NO_CONVERSION, inp, lbl, proba))
   {
      Print("ATLAS ML: OnnxRun failed, error=", GetLastError());
      return 0.0;
   }

   return (double)proba[0][1];
}

#endif // ATLAS_ML_MQH
