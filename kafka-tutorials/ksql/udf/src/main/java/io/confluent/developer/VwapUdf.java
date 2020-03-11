package io.confluent.developer;

import io.confluent.ksql.function.udf.Udf;
import io.confluent.ksql.function.udf.UdfDescription;
import io.confluent.ksql.function.udf.UdfParameter;

@UdfDescription(name = "vwap", description = "Volume weighted average price")
public class VwapUdf {

    @Udf(description = "vwap for market prices as integers, returns double")
    public double vwap(
            @UdfParameter(value = "bid")
            final int bid,
            @UdfParameter(value = "bidQty")
            final int bidQty,
            @UdfParameter(value = "ask")
            final int ask,
            @UdfParameter(value = "askQty")
            final int askQty) {
        return ((ask * askQty) + (bid * bidQty)) / (bidQty + askQty);
    }

    @Udf(description = "vwap for market prices as integers, returns double")
    public double vwap(
            @UdfParameter(value = "bid")
            final double bid,
            @UdfParameter(value = "bidQty")
            final int bidQty,
            @UdfParameter(value = "ask")
            final double ask,
            @UdfParameter(value = "askQty")
            final int askQty) {
        return ((ask * askQty) + (bid * bidQty)) / (bidQty + askQty);
    }
}