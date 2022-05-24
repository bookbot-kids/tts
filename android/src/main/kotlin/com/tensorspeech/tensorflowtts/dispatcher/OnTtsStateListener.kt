package com.tensorspeech.tensorflowtts.dispatcher

/**
 * @author []" "Xuefeng Ding"">&quot;mailto:xuefeng.ding@outlook.com&quot; &quot;Xuefeng Ding&quot;
 * Created 2020-07-28 14:25
 */
interface OnTtsStateListener {
    fun onTtsReady()
    fun onTtsStart(text: String?)
    fun onTtsStop()
}