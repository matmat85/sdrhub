import json
import signal
from pathlib import Path

from gnuradio import analog, blocks, filter, gr, soapy
from gnuradio.filter import firdes


def main():
    settings = json.loads(Path("/var/run/sdr/radio.json").read_text())
    args = settings["device_args"]
    source = soapy.source("driver=rtltcp", "fc32", 1, "rtltcp=" + args["rtltcp"], "", [""], [""])
    source.set_sample_rate(0, 1024000)
    source.set_frequency(0, settings["frequency"])
    source.set_gain_mode(0, True)
    decimator = filter.fir_filter_ccf(4, firdes.low_pass(1, 1024000, 100000, 20000))
    demodulator = analog.wfm_rcv(quad_rate=256000, audio_decimation=8)
    output = blocks.file_sink(gr.sizeof_float, "/dev/stdout", False)
    output.set_unbuffered(True)
    graph = gr.top_block("Live broadcast FM (mono)")
    graph.connect(source, decimator, demodulator, output)

    def stop(_signal, _frame):
        graph.stop()

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    graph.start()
    graph.wait()


if __name__ == "__main__":
    main()
