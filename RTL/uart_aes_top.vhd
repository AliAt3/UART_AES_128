library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;
use work.aes.all;

entity uart_aes_top is
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;
    i_RX_Serial : in  std_logic;
    o_TX_Serial : out std_logic
  );
end uart_aes_top;

architecture behavioral of uart_aes_top is
--state machine:
type top_top_state is (waiting_rx, enable_aes, wait_complete, TX_send,waiting_tx);
signal state : top_top_state := waiting_rx;

-- UART RX
signal rx_dv        : std_logic;
signal rx_byte      : std_logic_vector(7 downto 0);

-- UART TX
signal tx_dv        : std_logic := '0';
signal tx_byte      : std_logic_vector(7 downto 0);
signal tx_active    : std_logic;
signal tx_done      : std_logic;

-- AES Core
signal aes_input    : std_logic_vector(127 downto 0);
signal aes_key      : std_logic_vector(127 downto 0) := x"2b7e151628aed2a6abf7158809cf4f3c"; -- fixed key for now
signal aes_output   : std_logic_vector(127 downto 0);
signal aes_enable   : std_logic := '0';
signal aes_complete : std_logic;
signal inverse      : std_logic;

-- Control FSM
signal rx_count     : integer range 0 to 16 := 0;
signal tx_count     : integer range 0 to 15 := 0;
--signal state        : integer range 0 to 5 := 0;

-- UART Receiver
component UART_RX is
  generic (
    g_CLKS_PER_BIT : integer := 10417 -- Needs to be set correctly
  );
  port (
    i_Clk       : in  std_logic;
    i_RX_Serial : in  std_logic;
    o_RX_DV     : out std_logic;
    o_RX_Byte   : out std_logic_vector (7 downto 0)
  );
end component UART_RX;


--AES Core
component aes_top is
    port (  clk         : in std_logic; -- Clock.
            rst         : in std_logic; -- Reset.
            enable      : in std_logic; -- Enable.
            inverse     : in std_logic; -- 0 = encryption; 1 = decryption.
            key         : in std_logic_vector(127 downto 0); -- Secret key.
            input       : in std_logic_vector(127 downto 0); -- Input (plaintext or ciphertext).
            output      : out std_logic_vector(127 downto 0); -- Output (plaintext or ciphertext).
            complete    : out std_logic); -- Identify when the operation is complete.
end component aes_top;

-- UART Transmitter
component UART_TX is
  generic (
    g_CLKS_PER_BIT : integer := 10417  -- Needs to be set correctly (e.g., 10417 for 9600 baud @ 100MHz)
  );
  port (
    i_Clk       : in  std_logic;
    i_TX_DV     : in  std_logic;
    i_TX_Byte   : in  std_logic_vector(7 downto 0);
    o_TX_Active : out std_logic;
    o_TX_Serial : out std_logic;
    o_TX_Done   : out std_logic
  );
end component UART_TX;


begin

-- UART Receiver
uart_rx_inst : UART_RX
  generic map (g_CLKS_PER_BIT => 10417) -- For 9600 baud @ 100MHz
  port map (
    i_Clk     => clk,
    i_RX_Serial => i_RX_Serial,
    o_RX_DV   => rx_dv,
    o_RX_Byte => rx_byte
  );

-- AES Core
aes_core_inst : aes_top
  port map (
    clk      => clk,
    rst      => rst,
    enable   => aes_enable,
    inverse  => inverse,
    key      => aes_key,
    input    => aes_input,
    output   => aes_output,
    complete => aes_complete
  );

-- UART Transmitter
uart_tx_inst : UART_TX
  generic map (g_CLKS_PER_BIT => 10417)
  port map (
    i_Clk       => clk,
    i_TX_DV     => tx_dv,
    i_TX_Byte   => tx_byte,
    o_TX_Active => tx_active,
    o_TX_Serial => o_TX_Serial,
    o_TX_Done   => tx_done
  );
  
  
  
  process(clk, rst)
begin
  if rst = '1' then
    -- Reset logic
    rx_count <= 0;
    tx_count <= 0;
    state <= waiting_rx;
    aes_enable <= '0';
    tx_dv <= '0';
  elsif rising_edge(clk) then
    case state is

      when waiting_rx => -- WAITING FOR RX
        if rx_dv = '1' then
          if rx_count < 16 then
            aes_input(127 - rx_count*8 downto 120 - rx_count*8) <= rx_byte;
            rx_count <= rx_count + 1;
          elsif rx_count = 16 then
            inverse <= rx_byte(0); -- assuming inverse bit is LSB of last byte
            rx_count <= 0;
            state <= enable_aes;
          end if;
        end if;

      when enable_aes => -- ENABLE AES
        aes_enable <= '1';
        state <= wait_complete;

      when wait_complete => -- WAIT FOR COMPLETE
        if aes_complete = '1' then
          aes_enable <= '0';
          tx_count <= 0;
          state <= TX_send;
        end if;

      when TX_send => -- SEND OUTPUT VIA UART
        if tx_active = '0' and tx_dv = '0' then
          tx_byte <= aes_output(127 - tx_count*8 downto 120 - tx_count*8);
          tx_dv <= '1';
          state <= waiting_tx;
        end if;

      when waiting_tx =>
        tx_dv <= '0';
        if tx_done = '1' then
          if tx_count = 15 then
            state <= waiting_rx; -- back to idle
          else
            tx_count <= tx_count + 1;
            state <= TX_send;
          end if;
        end if;

      when others =>
        state <= waiting_rx;
    end case;
  end if;
end process;




end behavioral;