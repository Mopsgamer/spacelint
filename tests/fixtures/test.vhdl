entity hello is
end hello;

architecture sim of hello is
begin
    assert false report "Hello VHDL!" severity note;
end sim;
