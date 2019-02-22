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
-- WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 
 
library ieee;

use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity spi_slave is
	port
	(
		clk : in std_logic;
		reset : in std_logic;
		
		mosi : in std_logic;
		miso : out std_logic;
		sck : in std_logic;
		ss : in std_logic;
		
		
		data_rd : in std_logic_vector(31 downto 0);
		data_wr : out std_logic_vector(31 downto 0);
		data_wren : out std_logic;
		data_strobe : in std_logic
		
	);
end spi_slave;


architecture behv of spi_slave is
signal sync_mosi : std_logic_vector(1 downto 0);
signal sync_sck : std_logic_vector(1 downto 0);
signal sync_ss : std_logic_vector(1 downto 0);


begin

	process(clk)
	variable cnt : integer range 0 to 32 := 0;
	variable iwren : std_logic;
	variable i_miso : std_logic;
	variable i_shiftregister : std_logic_vector(31 downto 0);

	begin
		if rising_edge(clk) then
			if reset='1' then
				cnt := 0;
				data_wren <= '0';
				iwren := '0';
			else
				iwren := '0';
				
				sync_mosi <= sync_mosi(0) & mosi;
				sync_sck <= sync_sck(0) & sck;
				sync_ss <= sync_ss(0) & ss;

				if data_strobe = '1' then
					i_shiftregister := data_rd;
				end if;
				
				case sync_ss is
					when "11" => 
--						i_shiftregister := data_rd;
						cnt := 0;
--						i_flip := '0';
					when "10" =>
						miso <= i_shiftregister(31);
					when "01" =>
--						cnt := 0;
--						iwren := '1';
--						data_wr <= i_shiftregister;
					when "00" =>
						case sync_sck is
							when "01" => 
								i_shiftregister := i_shiftregister(30 downto 0) & mosi;
								cnt := cnt + 1;
								
								if cnt = 32 then
									cnt := 0;
									iwren := '1';
									data_wr <= i_shiftregister;
								end if;
							when "10" =>
								miso <= i_shiftregister(31);
							when others =>
						end case;
					when others =>
				end case;
				data_wren <= iwren;
			end if;
		end if;
	end process;
	

end behv;
