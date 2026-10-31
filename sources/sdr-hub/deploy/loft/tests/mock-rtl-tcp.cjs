const net = require('node:net');

net.createServer(socket => {
    console.log('CLIENT connected');
    const header = Buffer.alloc(12);
    header.write('RTL0');
    header.writeUInt32BE(5, 4);
    header.writeUInt32BE(29, 8);
    socket.write(header);
    let rate = 1024000;
    let frequency = 0;
    let sample = 0;
    let phase = 0;
    let pending = Buffer.alloc(0);
    socket.on('data', data => {
        pending = Buffer.concat([pending, data]);
        while (pending.length >= 5) {
            const command = pending[0];
            const value = pending.readUInt32BE(1);
            console.log(`COMMAND ${command} ${value}`);
            if (command === 2) rate = value;
            if (command === 1) frequency = value;
            pending = pending.subarray(5);
        }
    });
    const timer = setInterval(() => {
        if (!socket.destroyed && socket.writableLength < 1048576) {
            const data = Buffer.alloc(Math.min(Math.floor(rate * 2 / 50), 1048576), 128);
            if (frequency === 100000000) {
                for (let index = 0; index + 1 < data.length; index += 2) {
                    phase += 2 * Math.PI * 7500 * Math.sin(2 * Math.PI * 1000 * sample++ / rate) / rate;
                    phase %= 2 * Math.PI;
                    data[index] = Math.round(128 + 100 * Math.cos(phase));
                    data[index + 1] = Math.round(128 + 100 * Math.sin(phase));
                }
            }
            socket.write(data);
        }
    }, 20);
    socket.on('error', error => console.log(`CLIENT error: ${error.code}`));
    socket.on('close', () => clearInterval(timer));
}).listen(1234, '0.0.0.0', () => console.log('READY'));
