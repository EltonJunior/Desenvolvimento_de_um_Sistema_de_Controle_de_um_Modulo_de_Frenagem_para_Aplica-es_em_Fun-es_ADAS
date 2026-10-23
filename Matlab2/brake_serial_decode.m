function [omega, uIn, uOut, pwPsi, posMm, status, valid] = brake_serial_decode(line) %#codegen
%BRAKE_SERIAL_DECODE Parses "[ECHO],omega,u_in,u_out,pw_psi,pos_mm,status"
%   or "[LIVE],omega,u_in,u_out,pw_psi,pos_mm,status" lines from the AURIX.
    coder.varsize('line', [1 128], [0 1]);
    omega = 0; uIn = uint8(0); uOut = uint8(0);
    pwPsi = 0; posMm = 0; status = uint8(0); valid = false;

    headerEnd = strfind(line, ']');
    if isempty(headerEnd)
        return;
    end

    payload = strtrim(line(headerEnd(1)+1:end));
    coder.varsize('payload', [1 128], [0 1]);
    if isempty(payload) || payload(1) ~= ','
        return;
    end
    payload = payload(2:end);

    values = zeros(6, 1);
    coder.varsize('values', [6 1], [1 0]);
    [values, count] = sscanf(payload, '%f,%f,%f,%f,%f,%f');
    if count ~= 6
        return;
    end

    omega  = values(1);
    uIn    = uint8(values(2));
    uOut   = uint8(values(3));
    pwPsi  = values(4);
    posMm  = values(5);
    status = uint8(values(6));
    valid  = true;
end
