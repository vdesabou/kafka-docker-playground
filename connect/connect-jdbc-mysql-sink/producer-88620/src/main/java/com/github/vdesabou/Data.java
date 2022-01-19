
package com.github.vdesabou;

import java.util.HashMap;
import java.util.Map;
import javax.annotation.processing.Generated;
import com.fasterxml.jackson.annotation.JsonAnyGetter;
import com.fasterxml.jackson.annotation.JsonAnySetter;
import com.fasterxml.jackson.annotation.JsonIgnore;
import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonProperty;
import com.fasterxml.jackson.annotation.JsonPropertyOrder;

@JsonInclude(JsonInclude.Include.NON_NULL)
@JsonPropertyOrder({
    "agreementSerialId",
    "cardHolderId",
    "cardToken",
    "suffixPlasticCardNumber"
})
@Generated("jsonschema2pojo")
public class Data {

    @JsonProperty("agreementSerialId")
    private String agreementSerialId;
    @JsonProperty("cardHolderId")
    private String cardHolderId;
    @JsonProperty("cardToken")
    private String cardToken;
    @JsonProperty("suffixPlasticCardNumber")
    private String suffixPlasticCardNumber;
    @JsonIgnore
    private Map<String, Object> additionalProperties = new HashMap<String, Object>();

    @JsonProperty("agreementSerialId")
    public String getAgreementSerialId() {
        return agreementSerialId;
    }

    @JsonProperty("agreementSerialId")
    public void setAgreementSerialId(String agreementSerialId) {
        this.agreementSerialId = agreementSerialId;
    }

    @JsonProperty("cardHolderId")
    public String getCardHolderId() {
        return cardHolderId;
    }

    @JsonProperty("cardHolderId")
    public void setCardHolderId(String cardHolderId) {
        this.cardHolderId = cardHolderId;
    }

    @JsonProperty("cardToken")
    public String getCardToken() {
        return cardToken;
    }

    @JsonProperty("cardToken")
    public void setCardToken(String cardToken) {
        this.cardToken = cardToken;
    }

    @JsonProperty("suffixPlasticCardNumber")
    public String getSuffixPlasticCardNumber() {
        return suffixPlasticCardNumber;
    }

    @JsonProperty("suffixPlasticCardNumber")
    public void setSuffixPlasticCardNumber(String suffixPlasticCardNumber) {
        this.suffixPlasticCardNumber = suffixPlasticCardNumber;
    }

    @JsonAnyGetter
    public Map<String, Object> getAdditionalProperties() {
        return this.additionalProperties;
    }

    @JsonAnySetter
    public void setAdditionalProperty(String name, Object value) {
        this.additionalProperties.put(name, value);
    }

    @Override
    public String toString() {
        StringBuilder sb = new StringBuilder();
        sb.append(Data.class.getName()).append('@').append(Integer.toHexString(System.identityHashCode(this))).append('[');
        sb.append("agreementSerialId");
        sb.append('=');
        sb.append(((this.agreementSerialId == null)?"<null>":this.agreementSerialId));
        sb.append(',');
        sb.append("cardHolderId");
        sb.append('=');
        sb.append(((this.cardHolderId == null)?"<null>":this.cardHolderId));
        sb.append(',');
        sb.append("cardToken");
        sb.append('=');
        sb.append(((this.cardToken == null)?"<null>":this.cardToken));
        sb.append(',');
        sb.append("suffixPlasticCardNumber");
        sb.append('=');
        sb.append(((this.suffixPlasticCardNumber == null)?"<null>":this.suffixPlasticCardNumber));
        sb.append(',');
        sb.append("additionalProperties");
        sb.append('=');
        sb.append(((this.additionalProperties == null)?"<null>":this.additionalProperties));
        sb.append(',');
        if (sb.charAt((sb.length()- 1)) == ',') {
            sb.setCharAt((sb.length()- 1), ']');
        } else {
            sb.append(']');
        }
        return sb.toString();
    }

    @Override
    public int hashCode() {
        int result = 1;
        result = ((result* 31)+((this.agreementSerialId == null)? 0 :this.agreementSerialId.hashCode()));
        result = ((result* 31)+((this.cardHolderId == null)? 0 :this.cardHolderId.hashCode()));
        result = ((result* 31)+((this.suffixPlasticCardNumber == null)? 0 :this.suffixPlasticCardNumber.hashCode()));
        result = ((result* 31)+((this.additionalProperties == null)? 0 :this.additionalProperties.hashCode()));
        result = ((result* 31)+((this.cardToken == null)? 0 :this.cardToken.hashCode()));
        return result;
    }

    @Override
    public boolean equals(Object other) {
        if (other == this) {
            return true;
        }
        if ((other instanceof Data) == false) {
            return false;
        }
        Data rhs = ((Data) other);
        return ((((((this.agreementSerialId == rhs.agreementSerialId)||((this.agreementSerialId!= null)&&this.agreementSerialId.equals(rhs.agreementSerialId)))&&((this.cardHolderId == rhs.cardHolderId)||((this.cardHolderId!= null)&&this.cardHolderId.equals(rhs.cardHolderId))))&&((this.suffixPlasticCardNumber == rhs.suffixPlasticCardNumber)||((this.suffixPlasticCardNumber!= null)&&this.suffixPlasticCardNumber.equals(rhs.suffixPlasticCardNumber))))&&((this.additionalProperties == rhs.additionalProperties)||((this.additionalProperties!= null)&&this.additionalProperties.equals(rhs.additionalProperties))))&&((this.cardToken == rhs.cardToken)||((this.cardToken!= null)&&this.cardToken.equals(rhs.cardToken))));
    }

}
