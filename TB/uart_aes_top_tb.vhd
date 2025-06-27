library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;        

entity uart_aes_top_tb is
end uart_aes_top_tb;

architecture tb of uart_aes_top_tb is

  -- Clock & reset
  signal clk      : std_logic := '0';
  signal rst      : std_logic := '1';

  constant CLK_PERIOD : time := 10 ns;  -- 100 MHz

  -- UART_TX signals (driving uart_aes_top)
  signal tx_dv_tb     : std_logic := '0';
  signal tx_byte_tb   : std_logic_vector(7 downto 0) := (others => '0');
  signal tx_active    : std_logic;
  signal tx_done      : std_logic;

  -- uart_aes_top serial ports
  signal rx_serial    : std_logic := '1';
  signal tx_serial   : std_logic;

  -- UART_RX signals (receiving from uart_aes_top)
  signal rx_dv_tb     : std_logic;
  signal rx_byte_tb   : std_logic_vector(7 downto 0);

  -- Collecting output bytes
  type byte_array_16 is array (0 to 15) of std_logic_vector(7 downto 0);
  type byte_array_17 is array (0 to 16) of std_logic_vector(7 downto 0);
  signal received_bytes : byte_array_16 := (others => (others => '0'));
  signal rx_count       : integer range 0 to 16 := 0;

  -- Test plaintext (16 bytes). Last byte LSB is inverse bit.
  constant plain_bytes : byte_array_17 := (
    x"7d", x"f7", x"6b", x"0c", x"1a", x"b8",x"99",x"b3",x"3e",x"42",x"f0",x"47",x"b9",x"1b",x"54",x"6f",x"01");    -- LSB='0' or '1'
 
begin

  -- Clock generator
  clk_proc : process
  begin
    clk <= '0';
    wait for CLK_PERIOD/2;
    clk <= '1';
    wait for CLK_PERIOD/2;
  end process;

  -- Reset release
  rst_proc : process
  begin
    rst <= '1';
    wait for 100 ns;
    rst <= '0';
    wait;
  end process;

  -- Instantiate UART_TX
  uart_tx_inst : entity work.UART_TX
    generic map ( g_CLKS_PER_BIT => 10417 )
    port map (
      i_Clk       => clk,
      i_TX_DV     => tx_dv_tb,
      i_TX_Byte   => tx_byte_tb,
      o_TX_Active => tx_active,
      o_TX_Serial => rx_serial,   -- connect TX → uart_aes_top RX
      o_TX_Done   => tx_done
    );

  -- Instantiate your DUT
  uut : entity work.uart_aes_top
    port map (
      clk         => clk,
      rst         => rst,
      i_RX_Serial => rx_serial,
      o_TX_Serial => tx_serial
    );

  -- Instantiate UART_RX to capture the DUT output
  uart_rx_inst : entity work.UART_RX
    generic map ( g_CLKS_PER_BIT => 10417 )
    port map (
      i_Clk       => clk,
      i_RX_Serial => tx_serial,
      o_RX_DV     => rx_dv_tb,
      o_RX_Byte   => rx_byte_tb
    );

  -- Stimulus: send 16 bytes, one at a time
  stim_proc : process
  begin
    -- wait for reset deassert
    wait until rst = '0';
    wait for 50 ns;

    for i in 0 to 16 loop
      tx_byte_tb <= plain_bytes(i);
      tx_dv_tb   <= '1';
      wait until rising_edge(clk);
      tx_dv_tb   <= '0';
      -- wait for TX done
      wait until tx_done = '1';
      -- give UART_TX a moment to clear
      wait for CLK_PERIOD*2;
    end loop;

    -- now wait for 16 bytes back
    rx_count <= 0;
    while rx_count < 16 loop
      wait until rising_edge(clk);
      if rx_dv_tb = '1' then
        received_bytes(rx_count) <= rx_byte_tb;
        rx_count <= rx_count + 1;
      end if;
    end loop;

   
    wait;
  end process;

end	tb;
