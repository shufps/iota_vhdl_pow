-- IOTA Pearl Diver VHDL Port
--
-- 2018 by Thomas Pototschnig <microengineer18@gmail.com,
-- http://microengineer.eu
-- discord: pmaxuw#8292
--
-- Permission is hereby granted, free of charge, to any person obtaining
-- a copy of this software and associated documentation files (the
-- "Software"), to deal in the Software without restriction, including
-- without limitation the rights to use, copy, modify, merge, publish,
-- distribute, sublicense, and/or sell copies of the Software, and to
-- permit persons to whom the Software is furnished to do so, subject to
-- the following conditions:
-- 
-- The above copyright notice and this permission notice shall be
-- included in all copies or substantial portions of the Software.
-- 
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
-- EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
-- MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
-- NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
-- LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
-- OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
-- WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWAR

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity de1 is
	port (
		CLOCK_50 : in std_logic;
		reset : in std_logic;
		led_running : out std_logic;
		led_found : out std_logic;
		led_overflow : out std_logic;
--		////////////////////////	UART	////////////////////////
		spi1_mosi : in std_logic;
		spi1_sck : in std_logic;
		spi1_ss : in std_logic;
		spi1_miso : out std_logic;

		spi2_mosi : in std_logic;
		spi2_sck : in std_logic;
		spi2_ss : in std_logic;
		spi2_miso : out std_logic
		
	);
end;

architecture beh of de1 is

signal nreset : std_logic;



signal pll_clk : std_logic;
signal pll_reset : std_logic := '0';
signal pll_locked : std_logic;

signal spi1_data_tx : std_logic_vector(31 downto 0);
signal spi1_data_rx  : std_logic_vector(31 downto 0);
signal spi1_data_rx_en : std_logic;
signal spi1_data_strobe : std_logic;

signal spi2_data_tx : std_logic_vector(31 downto 0);
signal spi2_data_rx  : std_logic_vector(31 downto 0);
signal spi2_data_rx_en : std_logic;
signal spi2_data_strobe : std_logic;

signal spi_data_tx : std_logic_vector(31 downto 0);
signal spi_data_rx  : std_logic_vector(31 downto 0);
signal spi_data_rx_en : std_logic;
signal spi_data_strobe : std_logic;
		
signal spi1_data_hold : std_logic := '0';
signal spi2_data_hold : std_logic := '0';

signal pll_slow : std_logic;

component spi_slave
	port
	(
		clk : in std_logic;
		reset : in std_logic;
		
		mosi : in std_logic;
		miso : out std_logic;
		sck : in std_logic;
		ss : in std_logic;
		data_strobe : in std_logic;
		
		
		data_rd : in std_logic_vector(31 downto 0);
		data_wr : out std_logic_vector(31 downto 0);
		data_wren : out std_logic
	);
end component;

component pll
	PORT
	(
		areset		: IN STD_LOGIC  := '0';
		inclk0		: IN STD_LOGIC  := '0';
		c0		: OUT STD_LOGIC ;
		c1 : out std_logic;
		locked		: OUT STD_LOGIC 
	);
end component;

component curl
	port
	(
		clk : in std_logic;
		clk_slow : in std_logic;
		reset : in std_logic;
		
		spi_data_rx : in std_logic_vector(31 downto 0);
		spi_data_tx : out std_logic_vector(31 downto 0);
		spi_data_rxen : in std_logic;
		spi_data_strobe : out std_logic;

		overflow : out std_logic;
		running : out std_logic;
		found : out std_logic
	);
end component;

begin
	nreset <= not reset;


	pll0 : pll port map (
		areset => pll_reset,
		inclk0 => CLOCK_50,
		c0 => pll_clk,
		c1	=> pll_slow,
		locked => pll_locked
	);
	
	
	spi1 : spi_slave port map (
		clk => pll_slow,
		reset => nreset,
		
		mosi => spi1_mosi,
		miso => spi1_miso,
		sck => spi1_sck,
		ss => spi1_ss,
		data_strobe => spi1_data_strobe,
		
		data_rd => spi1_data_tx,
		data_wr => spi1_data_rx,
		data_wren => spi1_data_rx_en
	);
	
	spi2 : spi_slave port map (
		clk => pll_slow,
		reset => nreset,
		
		mosi => spi2_mosi,
		miso => spi2_miso,
		sck => spi2_sck,
		ss => spi2_ss,
		data_strobe => spi2_data_strobe,
		
		data_rd => spi2_data_tx,
		data_wr => spi2_data_rx,
		data_wren => spi2_data_rx_en
	);	
	
	curl0 : curl port map (
		clk => pll_clk,
		reset => nreset,
		clk_slow => pll_slow,
		
		spi_data_rx => spi_data_rx,
		spi_data_tx => spi_data_tx,
		spi_data_rxen => spi_data_rx_en,
		spi_data_strobe => spi_data_strobe,
		
		overflow => led_overflow,
		running => led_running,
		found => led_found
	);
	
	
	process(pll_slow)
		variable state : integer range 0 to 15 := 0;
		variable rxen1 : std_logic := '0';
		variable rxen2 : std_logic := '0';
		variable rxdata1 : std_logic_vector(31 downto 0) := (others => '0');
		variable rxdata2 : std_logic_vector(31 downto 0) := (others => '0');
	begin
		if rising_edge(pll_slow) then
			if nreset='1' then
				state := 0;
			else 
--				spi1_data_strobe <= spi_data_strobe;
--				spi1_data_tx <= spi_data_tx;
--				spi2_data_strobe <= spi_data_strobe;
--				spi2_data_tx <= spi_data_tx;

				spi_data_rx_en <= '0';
				spi1_data_strobe <= '0';
				spi2_data_strobe <= '0';
				
				-- save both independent
				if spi1_data_rx_en = '1' then
					rxen1 := '1';
					rxdata1 := spi1_data_rx;
				end if;
				
				if spi2_data_rx_en = '1' then
					rxen2 := '1';
					rxdata2 := spi2_data_rx;
				end if;

				case state is 
				when 0 =>
					-- priorize spi1
					if rxen1 = '1' then
						rxen1 := '0';
						spi_data_rx_en <= '1';
						spi_data_rx <= rxdata1;
						if rxdata1(31) = '1' then	-- wait for data
							state := 1;
						end if;
					elsif rxen2 = '1' then
						rxen2 := '0';
						spi_data_rx_en <= '1';
						spi_data_rx <= rxdata2;
						if rxdata2(31) = '1' then	-- wait for data
							state := 5;
						end if;
					end if;					
				when 1 =>	-- wait for data from command decoder
					if spi_data_strobe = '1' then
						spi1_data_tx <= spi_data_tx;
						spi1_data_strobe <= '1';
						state := 0;
					end if;
					
				when 5 =>	-- wait for data from command decoder
					if spi_data_strobe = '1' then
						spi2_data_tx <= spi_data_tx;
						spi2_data_strobe <= '1';
						state := 0;
					end if;
				when others =>
					state := 0;
				end case;
			end if;
		end if;
	end process;

end architecture;
