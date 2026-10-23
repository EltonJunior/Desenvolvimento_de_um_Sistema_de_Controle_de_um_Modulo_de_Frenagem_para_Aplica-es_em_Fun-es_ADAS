function msg = brake_serial_encode(mode, omega, uIn, uOut) %#codegen
%BRAKE_SERIAL_ENCODE Builds a command line for the AURIX brake UART protocol.
%   mode = 'ECHO' -> "[ECHO]<omega,u_in,u_out>"  (loopback test, no hardware)
%   mode = 'LIVE' -> "OMEGA_P=omega,U_IN=u_in,U_OUT=u_out" (real control)
    coder.varsize('msg', [1 48], [0 1]); % length depends on digit count, bound it for codegen
    if strcmpi(mode, 'ECHO')
        msg = sprintf('[ECHO]<%.2f,%u,%u>\n', omega, uint8(uIn), uint8(uOut));
    else
        msg = sprintf('OMEGA_P=%.2f,U_IN=%u,U_OUT=%u\n', omega, uint8(uIn), uint8(uOut));
    end
end
