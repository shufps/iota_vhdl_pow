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

library ieee;
 
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.index_table.all;
 
entity curl is
	generic
	(
		VERSION_MAJOR : integer := 1;
		VERSION_MINOR : integer := 1;
		HASH_LENGTH : integer := 243;
		STATE_LENGTH : integer := 729; -- 3 * HASH_LENGTH;
		NONCE_LENGTH : integer := 81; -- HASH_LENGTH / 3;
		NUMBER_OF_ROUNDS : integer := 81;
		PARALLEL : integer := 7;
		INTERN_NONCE_LENGTH : integer	:= 32;
		BITS_MIN_WEIGHT_MAGINUTE_MAX : integer := 26;
		DATA_WIDTH : integer := 9;
		NONCE_OFFSET : integer := 162;	-- we hope it nevery changes
		USE_CRC : integer := 1	-- CRC32 optionally for tx data 
	);

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
	
end curl;

architecture behv of curl is

component crc is 
	port ( 
		data_in : in std_logic_vector (31 downto 0);
		crc_en : in std_logic;
		crc_clr : in std_logic;
		rst : in std_logic;
		clk : in std_logic;
		crc_out : out std_logic_vector (31 downto 0)
	);
end component;


subtype state_vector_type is std_logic_vector(PARALLEL-1 downto 0);
subtype mid_state_vector_type is std_logic_vector(DATA_WIDTH-1 downto 0);
subtype min_weight_magnitude_type is std_logic_vector(BITS_MIN_WEIGHT_MAGINUTE_MAX-1 downto 0);

type curl_state_array is array(integer range <>) of state_vector_type;
type mid_state_array is array(integer range <>) of mid_state_vector_type;
type min_weight_magnitude_array is array(integer range<>) of min_weight_magnitude_type;

signal curl_state_low : curl_state_array(STATE_LENGTH-1 downto 0);
signal curl_state_high : curl_state_array(STATE_LENGTH-1 downto 0);

signal data_low : mid_state_array((HASH_LENGTH/DATA_WIDTH)-1 downto 0);
signal data_high : mid_state_array((HASH_LENGTH/DATA_WIDTH)-1 downto 0);


signal curl_mid_state_low : std_logic_vector(STATE_LENGTH-1 downto 0);
signal curl_mid_state_high : std_logic_vector(STATE_LENGTH-1 downto 0);

signal flag_running : std_logic := '0';
signal flag_overflow : std_logic := '0';
signal flag_found : std_logic := '0';
signal flag_start : std_logic := '0';

signal flag_curl_finished : std_logic := '0';

type binary_nonce_array is array(integer range<>) of unsigned(INTERN_NONCE_LENGTH-1 downto 0);


signal binary_nonce : unsigned(INTERN_NONCE_LENGTH-1 downto 0);	
signal mask : state_vector_type;
signal min_weight_magnitude : min_weight_magnitude_type;

signal i_binary_nonce : unsigned(INTERN_NONCE_LENGTH-1 downto 0);	
signal tmp_weight_magnitude : min_weight_magnitude_array(0 to PARALLEL-1);

signal flag_curl_reset : std_logic;
signal flag_curl_write : std_logic;
signal flag_curl_do_curl : std_logic;

signal imask : state_vector_type;

signal crc_data_in : std_logic_vector (31 downto 0);
signal crc_en : std_logic := '0';
signal crc_data_out : std_logic_vector (31 downto 0);
signal crc_clr : std_logic := '0';

function expand(b : std_logic) 
	return state_vector_type is
begin
	if b = '1' then
		return (others => '1');
	else
		return (others => '0');
	end if;
end expand;


begin
	crc0: if USE_CRC = 1 generate
		crc0 : crc port map (
			data_in => crc_data_in,
			crc_en => crc_en,
			rst => reset,
			crc_clr => crc_clr,
			clk => clk_slow,
			crc_out => crc_data_out
		);
	end generate;
	
	
	overflow <= flag_overflow;
	running <= flag_running;
	found <= flag_found;
	
	process (clk_slow)
	-- because it looks prettier
		variable spi_cmd : std_logic_vector(5 downto 0);
		variable addrptr : unsigned(7 downto 0) := x"00";
	begin
		if rising_edge(clk_slow) then
			if reset='1' then
				min_weight_magnitude <= (others => '0');
				flag_start <= '0';
				spi_data_tx <= (others => '0');
				addrptr := x"00";
			else
				flag_start <= '0';
				flag_curl_reset <= '0';
				flag_curl_write <= '0';
				flag_curl_do_curl <= '0';
				spi_data_strobe <= '0';

				if USE_CRC = 1 then
					crc_en <= '0';
					crc_clr <= '0';
				end if;
				
-- new spi data received
				if spi_data_rxen = '1' then
					spi_cmd := spi_data_rx(31 downto 26);
					case spi_cmd is
						when "000000" => -- nop (mainly for reading back data)
						when "000001" => -- start / stop
							flag_start <= spi_data_rx(0);
							flag_curl_reset <= spi_data_rx(1);
							flag_curl_write <= spi_data_rx(2);
							flag_curl_do_curl <= spi_data_rx(3);
						when "000010" =>	-- reset write address
							addrptr := (others => '0'); 
							if USE_CRC = 1 then -- clear CRC32
								crc_clr <= '1';
							end if;
						when "000100" =>	-- write to data buffer
							if (addrptr <= (HASH_LENGTH/DATA_WIDTH)-1) then
								data_low(to_integer(addrptr)) <= spi_data_rx(DATA_WIDTH-1 downto 0);
								data_high(to_integer(addrptr)) <= spi_data_rx(DATA_WIDTH+8 downto DATA_WIDTH);
							end if;
							if USE_CRC = 1 then -- if CRC32 is used, update checksum
								crc_data_in <= "000000" & std_logic_vector(addrptr) & spi_data_rx(DATA_WIDTH+8 downto 0);
								crc_en <= '1';
							end if;
							addrptr := addrptr + 1;
						when "001000" =>
							min_weight_magnitude <= spi_data_rx(BITS_MIN_WEIGHT_MAGINUTE_MAX-1 downto 0);
						when "100001" =>	-- read flags
							spi_data_tx(3 downto 0) <= flag_curl_finished & flag_overflow & flag_found & flag_running;
							spi_data_tx(7 downto 4) <= std_logic_vector(to_unsigned(PARALLEL, 4));
							spi_data_tx(8+(PARALLEL-1) downto 8) <= mask;
							spi_data_tx(31 downto 28) <= std_logic_vector(to_unsigned(VERSION_MAJOR, 4));
							spi_data_tx(27 downto 24) <= std_logic_vector(to_unsigned(VERSION_MINOR, 4));
						when "100010" => -- read nonce
							spi_data_tx(INTERN_NONCE_LENGTH-1 downto 0) <= std_logic_vector(binary_nonce);
						when "100100" => -- read crc32
							if USE_CRC = 1 then
								spi_data_tx <= crc_data_out;
							end if;
						when others =>
					end case; 
					spi_data_strobe <= spi_cmd(5);
				end if;
			end if; 
		end if;
	end process;
	
	process (clk_slow)
		variable	state : integer range 0 to 7 := 0;
		variable round : integer range 0 to 127 := 0;
		variable tmp_index : integer range 0 to 1023;
		
		variable alpha : std_logic_vector(STATE_LENGTH-1 downto 0);
		variable beta : std_logic_vector(STATE_LENGTH-1 downto 0);
		variable gamma : std_logic_vector(STATE_LENGTH-1 downto 0);
		variable delta : std_logic_vector(STATE_LENGTH-1 downto 0);
		
	begin
		if rising_edge(clk_slow) then
			if reset='1' then
				state := 0;
			else
				case state is
					when 0 =>
						round := NUMBER_OF_ROUNDS;
						flag_curl_finished <= '1';

						if flag_curl_write = '1' then 
							for I in 0 to (HASH_LENGTH/DATA_WIDTH)-1 loop
								for J in 0 to DATA_WIDTH-1 loop
									tmp_index := I*DATA_WIDTH+J;
									curl_mid_state_low(tmp_index) <= data_low(I)(J);
									curl_mid_state_high(tmp_index) <= data_high(I)(J);
								end loop;
							end loop;
						elsif flag_curl_reset='1' then
							curl_mid_state_low <= (others => '1');
							curl_mid_state_high <= (others => '1');
						end if;

						if flag_curl_do_curl = '1' then
							round := NUMBER_OF_ROUNDS;
							flag_curl_finished <= '0';
							state := 1;
						end if;
					when 1 =>	-- do the curl hash round without any copying needed
						if round = 1 then
							state := 0;
						end if;
						for I in 0 to STATE_LENGTH-1 loop
							alpha(I) := curl_mid_state_low(index_table(I));
							beta(I) := curl_mid_state_high(index_table(I));
							gamma(I) := curl_mid_state_high(index_table(I+1));
							
							delta(I) := (alpha(I) or (not gamma(I))) and (curl_mid_state_low(index_table(I+1)) xor beta(I));

							curl_mid_state_low(I) <= not delta(I);
							curl_mid_state_high(I) <= (alpha(I) xor gamma(I)) or delta(I);
						end loop;
						round := round - 1;
					when others =>
						state := 0;
				end case;
			end if;
		end if;
	end process;
	
	process (clk)
		variable	state : integer range 0 to 63 := 0;
		variable round : integer range 0 to 127 := 0;

		
		variable i_min_weight_magnitude : min_weight_magnitude_type;

		-- temporary registers get optimized away
		variable alpha : curl_state_array(STATE_LENGTH-1 downto 0);
		variable beta : curl_state_array(STATE_LENGTH-1 downto 0);
		variable gamma : curl_state_array(STATE_LENGTH-1 downto 0);
		variable delta : curl_state_array(STATE_LENGTH-1 downto 0);

		variable tmp_highest_bit : integer range 0 to 31;
	begin
		if rising_edge(clk) then
			if reset='1' then
				state := 0;
				round := 0;
				flag_found <= '0';
				flag_running <= '0';
				flag_overflow <= '0';
				binary_nonce <= (others => '0');
				mask <= (others => '0');
--				curl_state_low <= (others => (others => '0'));
--				curl_state_high <= (others => (others => '0'));
--				tmp_weight_magnitude := (others => (others => '0'));
				i_binary_nonce <= (others => '0');
				imask <= (others => '0');
--				i_min_weight_magnitude := (others => '0');
--				alpha := (others => (others => '0'));
--				beta := (others => (others => '0'));
--				gamma := (others => (others => '0'));
--				delta := (others => (others => '0'));
--				tmp_index := 0;
				tmp_weight_magnitude <= (others => (others => '0'));
			else
				case state is
					when 0 =>
						flag_running <= '0';
					when others =>
						flag_running <= '1';
				end case;
				
				case state is
					when 0 =>
--						flag_running <= '0';
						if flag_start = '1' then
							i_binary_nonce <= x"00000000";
--							flag_running <= '1';
							state := 1;
						end if;
						
					-- do PoW
					when 1 =>	-- copy mid state and insert nonce
						i_min_weight_magnitude := min_weight_magnitude;
						flag_found <= '0';
						flag_overflow <= '0';
						binary_nonce <= i_binary_nonce;						
						-- pipelining
						i_binary_nonce <= i_binary_nonce + 1;

--						-- copy and fully expand mid-state to curl-state
						for I in 0 to STATE_LENGTH-1 loop
							if  I < NONCE_OFFSET or I > NONCE_OFFSET + NONCE_LENGTH - 1 then
								curl_state_low(I) <= expand(curl_mid_state_low(I));
								curl_state_high(I) <= expand(curl_mid_state_high(I));
							end if;
						end loop;

--						for I in 0 to NONCE_OFFSET-1 loop
--							curl_state_low(I) <= expand(curl_mid_state_low(I));
--							curl_state_high(I) <= expand(curl_mid_state_high(I));
--						end loop;
--
--						for I in NONCE_OFFSET + NONCE_LENGTH to STATE_LENGTH-1 loop
--							curl_state_low(I) <= expand(curl_mid_state_low(I));
--							curl_state_high(I) <= expand(curl_mid_state_high(I));
--						end loop;						
						
   
						-- fill all ... synthesizer is smart enough to optimize away what is not needed
						for I in NONCE_OFFSET to NONCE_OFFSET + NONCE_LENGTH - 1 loop
							curl_state_low(I) <= expand('1');
							curl_state_high(I) <= expand('1');
						end loop;
						
						-- calculate log2(x) by determining the place of highest set bit
						-- this is calculated on constants, so no logic needed
						tmp_highest_bit := 0;
						for I in 0 to 31 loop	-- 32 is enough ...^^
							if to_unsigned(PARALLEL-1, 32)(I) = '1' then
								tmp_highest_bit := I;
							end if;
						end loop;
	
						-- insert 
						for J in 0 to 23 loop
							curl_state_low(NONCE_OFFSET+J) <= expand(signature(J)(0));
							curl_state_high(NONCE_OFFSET+J) <= expand(signature(J)(1));
						end loop;
	
--						-- generate bitmuster in first trit-arrays of nonce depending on PARALLEL setting
						-- this is calculated on constants, so no logic needed
						for I in 0 to PARALLEL-1 loop
							for J in 0 to tmp_highest_bit loop
								curl_state_low(NONCE_OFFSET+J+24)(I) <= to_unsigned(I, tmp_highest_bit+1)(J);
								curl_state_high(NONCE_OFFSET+J+24)(I) <= not to_unsigned(I, tmp_highest_bit+1)(J);
							end loop;
						end loop;
						
						-- insert and convert binary nonce to ternary nonce
						-- It's a fake ternary nonce but integer-values are strictly monotonously rising 
						-- with integer values of binary nonce.
						-- Doesn't bring the exact same result like reference implementation with real
						-- ternary adder - but it doesn't matter and it is way faster.
						-- conveniently put nonce counter at the end of nonce
						for I in 0 to INTERN_NONCE_LENGTH-1 loop
							curl_state_low(NONCE_OFFSET + NONCE_LENGTH - INTERN_NONCE_LENGTH + I) <= expand(i_binary_nonce(I));
							curl_state_high(NONCE_OFFSET + NONCE_LENGTH - INTERN_NONCE_LENGTH + I) <= not expand(i_binary_nonce(I));
						end loop;

						-- initialize round-counter
						round := NUMBER_OF_ROUNDS;
						if i_binary_nonce = x"ffffffff" then
							flag_overflow <= '1';
							state := 0;
						else
							state := 2;
						end if;
					when 2 =>	-- do the curl hash round without any copying needed
						if round = 1 then
							state := 3;
						end if;
						for I in 0 to STATE_LENGTH-1 loop
							alpha(I) := curl_state_low(index_table(I));
							beta(I) := curl_state_high(index_table(I));
							gamma(I) := curl_state_high(index_table(I+1));
							
							delta(I) := (alpha(I) or (not gamma(I))) and (curl_state_low(index_table(I+1)) xor beta(I));

							curl_state_low(I) <= not delta(I);
							curl_state_high(I) <= (alpha(I) xor gamma(I)) or delta(I);
						end loop;
						round := round - 1;
					when 3 =>  -- find out which solution - if any
	
						-- transform "vertical" trits to "horizontal" bits
						-- and compare with min weight magnitude mask
						for I in 0 to PARALLEL-1 loop
							for J in 0 to BITS_MIN_WEIGHT_MAGINUTE_MAX-1 loop
								tmp_weight_magnitude(I)(J) <= curl_state_low(HASH_LENGTH - 1 - J)(I) and curl_state_high(HASH_LENGTH - 1 - J)(I) and i_min_weight_magnitude(J);
							end loop;
						end loop;

						-- pipelining
						imask <= (others => '0');
						for I in 0 to PARALLEL-1 loop
							if tmp_weight_magnitude(I) = i_min_weight_magnitude then
								imask(I) <= '1';
							end if;
						end loop;
						
						-- pipelining
						if unsigned(imask) = 0 then
							state :=1;
						else
							flag_found <= '1';
							mask <= imask;
							state :=0;
						end if;
					when others =>
						state := 0;
				end case;
			end if;
		end if;
	end process;
end behv;
