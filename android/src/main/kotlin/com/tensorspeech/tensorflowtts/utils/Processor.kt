package com.tensorspeech.tensorflowtts.utils

import android.util.Log
import com.tensorspeech.tensorflowtts.utils.NumberNorm.numToString
import com.tensorspeech.tensorflowtts.utils.NumberNorm.toOrdinal
import java.nio.charset.StandardCharsets
import java.util.*
import java.util.regex.Pattern

/**
 * @author []" "M. Yusuf Sarıgöz"">&quot;mailto:yusufsarigoz@gmail.com&quot; &quot;M. Yusuf Sarıgöz&quot;
 * Created 2020-07-25 17:25
 */
class Processor {
    private fun symbolsToSequence(symbols: String): List<Int?> {
        val sequence: MutableList<Int?> = ArrayList()
        for (i in 0 until symbols.length) {
            val id = SYMBOL_TO_ID[symbols[i].toString()]
            if (id == null) {
                Log.e(TAG, "symbolsToSequence: id is not found for " + symbols[i])
            } else {
                sequence.add(id)
            }
        }
        return sequence
    }

    private fun arpabetToSequence(symbols: String?): List<Int?> {
        val sequence: MutableList<Int?> = ArrayList()
        if (symbols != null) {
            val `as` = symbols.split(" ".toRegex()).toTypedArray()
            for (s in `as`) {
                sequence.add(SYMBOL_TO_ID["@$s"])
            }
        }
        return sequence
    }

    private fun convertToAscii(text: String): String {
        val bytes = text.toByteArray(StandardCharsets.US_ASCII)
        return String(bytes)
    }

    private fun collapseWhitespace(text: String): String {
        return text.replace("\\s+".toRegex(), " ")
    }

    private fun expandAbbreviations(text: String): String {
        var text = text
        for ((key, value) in ABBREVIATIONS) {
            text = text.replace("\\b" + key + "\\.".toRegex(), value)
        }
        return text
    }

    private fun removeCommasFromNumbers(inputText: String): String {
        var text = inputText
        val m = COMMA_NUMBER_RE.matcher(text)
        while (m.find()) {
            val s = m.group().replace(",".toRegex(), "")
            text = text.replaceFirst(m.group().toRegex(), s)
        }
        return text
    }

    private fun expandPounds(text: String): String {
        var text = text
        val m = POUNDS_RE.matcher(text)
        while (m.find()) {
            text = text.replaceFirst(m.group().toRegex(), m.group() + " pounds")
        }
        return text
    }

    private fun expandDollars(text: String): String {
        var text = text
        val m = DOLLARS_RE.matcher(text)
        while (m.find()) {
            var dollars = "0"
            var cents = "0"
            var spelling = ""
            val s = m.group().substring(1)
            val parts = s.split("\\.".toRegex()).toTypedArray()
            if (!s.startsWith(".")) {
                dollars = parts[0]
            }
            if (!s.endsWith(".") && parts.size > 1) {
                cents = parts[1]
            }
            if ("0" != dollars) {
                spelling += parts[0] + " dollars "
            }
            if ("0" != cents && "00" != cents) {
                spelling += parts[1] + " cents "
            }
            text = text.replaceFirst("\\\\" + m.group().toRegex(), spelling)
        }
        return text
    }

    private fun expandDecimals(text: String): String {
        var text = text
        val m = DECIMAL_RE.matcher(text)
        while (m.find()) {
            val s = m.group().replace("\\.".toRegex(), " point ")
            text = text.replaceFirst(m.group().toRegex(), s)
        }
        return text
    }

    private fun expandOrdinals(text: String): String {
        var text = text
        val m = ORDINAL_RE.matcher(text)
        while (m.find()) {
            val s = m.group().substring(0, m.group().length - 2)
            val l = java.lang.Long.valueOf(s)
            val spelling = toOrdinal(l)
            text = text.replaceFirst(m.group().toRegex(), spelling)
        }
        return text
    }

    private fun expandCardinals(text: String): String {
        var text = text
        val m = NUMBER_RE.matcher(text)
        while (m.find()) {
            val l = java.lang.Long.valueOf(m.group())
            val spelling = numToString(l)
            text = text.replaceFirst(m.group().toRegex(), spelling)
        }
        return text
    }

    private fun expandNumbers(text: String): String {
        var text = text
        text = removeCommasFromNumbers(text)
        text = expandPounds(text)
        text = expandDollars(text)
        text = expandDecimals(text)
        text = expandOrdinals(text)
        text = expandCardinals(text)
        return text
    }

    private fun cleanTextForEnglish(text: String): String {
        var text = text
        text = convertToAscii(text)
        text = text.lowercase(Locale.getDefault())
        text = expandAbbreviations(text)
        try {
            text = expandNumbers(text)
        } catch (e: Exception) {
            Log.d(TAG, "Failed to convert numbers", e)
        }
        text = collapseWhitespace(text)
        Log.d(TAG, "text preprocessed: $text")
        return text
    }

    fun textToIds(inputText: String?): IntArray {
        var text = inputText
        val sequence: MutableList<Int?> = ArrayList()
        while (!text.isNullOrEmpty()) {
            val m = CURLY_RE.matcher(text)
            if (!m.find()) {
                sequence.addAll(symbolsToSequence(cleanTextForEnglish(text)))
                break
            }
            sequence.addAll(symbolsToSequence(cleanTextForEnglish(m.group(1) ?: "")))
            sequence.addAll(arpabetToSequence(m.group(2)))
            text = m.group(3)
        }
        val size = sequence.size
        val tmp = sequence.toTypedArray()
        val ids = IntArray(size)
        for (i in 0 until size) {
            ids[i] = tmp[i]!!
        }
        return ids
    }

    companion object {
        private const val TAG = "processor"
        private val VALID_SYMBOLS = arrayOf(
            "AA",
            "AA0",
            "AA1",
            "AA2",
            "AE",
            "AE0",
            "AE1",
            "AE2",
            "AH",
            "AH0",
            "AH1",
            "AH2",
            "AO",
            "AO0",
            "AO1",
            "AO2",
            "AW",
            "AW0",
            "AW1",
            "AW2",
            "AY",
            "AY0",
            "AY1",
            "AY2",
            "B",
            "CH",
            "D",
            "DH",
            "EH",
            "EH0",
            "EH1",
            "EH2",
            "ER",
            "ER0",
            "ER1",
            "ER2",
            "EY",
            "EY0",
            "EY1",
            "EY2",
            "F",
            "G",
            "HH",
            "IH",
            "IH0",
            "IH1",
            "IH2",
            "IY",
            "IY0",
            "IY1",
            "IY2",
            "JH",
            "K",
            "L",
            "M",
            "N",
            "NG",
            "OW",
            "OW0",
            "OW1",
            "OW2",
            "OY",
            "OY0",
            "OY1",
            "OY2",
            "P",
            "R",
            "S",
            "SH",
            "T",
            "TH",
            "UH",
            "UH0",
            "UH1",
            "UH2",
            "UW",
            "UW0",
            "UW1",
            "UW2",
            "V",
            "W",
            "Y",
            "Z",
            "ZH"
        )
        private val CURLY_RE = Pattern.compile("(.*?)\\{(.+?)\\}(.*)")
        private val COMMA_NUMBER_RE = Pattern.compile("([0-9][0-9\\,]+[0-9])")
        private val DECIMAL_RE = Pattern.compile("([0-9]+\\.[0-9]+)")
        private val POUNDS_RE = Pattern.compile("£([0-9\\,]*[0-9]+)")
        private val DOLLARS_RE = Pattern.compile("\\$([0-9.\\,]*[0-9]+)")
        private val ORDINAL_RE = Pattern.compile("[0-9]+(st|nd|rd|th)")
        private val NUMBER_RE = Pattern.compile("[0-9]+")
        private const val PAD = "_"
        private const val EOS = "~"
        private const val SPECIAL = "-"
        private val PUNCTUATION = "!'(),.:;? ".split("".toRegex()).toTypedArray()
        private val LETTERS =
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz".split("".toRegex())
                .toTypedArray()
        private val SYMBOLS: MutableList<String> = ArrayList()
        private val ABBREVIATIONS: MutableMap<String, String> = HashMap()
        private val SYMBOL_TO_ID: MutableMap<String, Int> = HashMap()
    }

    init {
        SYMBOLS.add(PAD)
        SYMBOLS.add(SPECIAL)
        for (p in PUNCTUATION) {
            if ("" != p) {
                SYMBOLS.add(p)
            }
        }
        for (l in LETTERS) {
            if ("" != l) {
                SYMBOLS.add(l)
            }
        }
        for (validSymbol in VALID_SYMBOLS) {
            SYMBOLS.add("@$validSymbol")
        }
        SYMBOLS.add(EOS)
        for (i in SYMBOLS.indices) {
            SYMBOL_TO_ID[SYMBOLS[i]] = i
        }
        ABBREVIATIONS["mrs"] = "misess"
        ABBREVIATIONS["mr"] = "mister"
        ABBREVIATIONS["dr"] = "doctor"
        ABBREVIATIONS["st"] = "saint"
        ABBREVIATIONS["co"] = "company"
        ABBREVIATIONS["jr"] = "junior"
        ABBREVIATIONS["maj"] = "major"
        ABBREVIATIONS["gen"] = "general"
        ABBREVIATIONS["drs"] = "doctors"
        ABBREVIATIONS["rev"] = "reverend"
        ABBREVIATIONS["lt"] = "lieutenant"
        ABBREVIATIONS["hon"] = "honorable"
        ABBREVIATIONS["sgt"] = "sergeant"
        ABBREVIATIONS["capt"] = "captain"
        ABBREVIATIONS["esq"] = "esquire"
        ABBREVIATIONS["ltd"] = "limited"
        ABBREVIATIONS["col"] = "colonel"
        ABBREVIATIONS["ft"] = "fort"
    }
}