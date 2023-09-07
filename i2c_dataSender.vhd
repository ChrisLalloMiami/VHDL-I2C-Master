-- Packet sender for the i2c_master top-level, sending individual
-- messages and alerting the top-level that an acknowledge is ready.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;


entity i2c_dataSender is
    port (
        clk          : in std_logic;                     -- 100 MHZ clock provided by top-level
        rst          : in std_logic;                     -- Reset signal
        
        scl          : out std_logic := '1';             -- 1 MHz serial clock
        sda          : out std_logic := '1';             -- Output for serial data to top-level
        
        byte         : in std_logic_vector (7 downto 0); -- The byte of the current message to send
        enable       : in std_logic;                     -- Signal to begin sending process
        sendStartBit : in boolean;                       -- Determines whether or not to send the sequence start bit
        sendStopBit  : in boolean;                       -- Determines whether or not to send the sequence stop bit
        ackReady     : out boolean;                      -- Signal to flag top-level to read ACK from slave
        done         : out boolean;                      -- Signal to alert top-level to send another byte
        setTristate  : out boolean                       -- Signal to alert top-level to prepare tristate for read
    );
end i2c_dataSender;

architecture Behavioral of i2c_dataSender is

    type state_type is (waiting, startSDA, startSCL, sclDown, sclUp, waitForAck, readAck, lastLow, stopSCL, stopSDA);
    signal state      : state_type;

    signal bitCounter : integer := 8; -- Current bit of the provided byte
    signal counter    : integer := 0; -- Counter for SCL timing

begin
    -- Handles all state transitions
    process(clk, rst)
    begin
        if rst = '1' then
            setTristate <= false;
            state <= waiting;
        elsif rising_edge(clk) then
            case state is
                when waiting =>
                    if enable = '1' and sendStartBit then
                        setTristate <= false;
                        state <= startSDA;
                    elsif enable = '1' and not sendStartBit  then
                        state <= sclDown;
                    end if;
                ----------------------------------
                -- startSDA and startSCL write start bit
                ----------------------------------
                when startSDA =>
                    if counter = 49 then
                        state <= startSCL;
                    end if;
                    
                when startSCL =>
                    if counter = 48 then -- Only count to 48, because we transition to next state before adjusting SCL
                        state <= sclDown;
                    end if;
                ----------------------------------
                
                -- Hold SCL low for half a cycle
                when sclDown =>
                    if counter = 49 then
                        state <= sclUp;
                    end if;
                    
                -- Hold SCL high for half a cycle
                when sclUp =>
                    if counter = 49 then
                        if bitCounter = 0 then
                            state <= waitForAck;
                            setTristate <= true;
                        else
                            state <= sclDown;
                        end if;
                    end if;
                    
                -- Hold SCL low for half a cycle
                when waitForAck =>
                    setTristate <= false;
                    if counter = 49 then
                        state <= readAck;
                    end if;
                    
                -- Hold SCL high for half a cycle, then read ACK
                when readAck =>
                    if counter = 49 then
                        if sendStopBit then
                            state <= lastLow;
                        elsif enable = '1' and sendStopBit = false then
                            state <= sclDown;
                        end if;
                    end if;
                    
                -- Holds SCL and SDA low for half a cycle before sending a stop bit
                when lastLow =>
                    if counter = 49 then
                        state <= stopSCL;
                    end if;
                
                ----------------------------------
                -- stopSCL and stopSDA write stop bit
                ----------------------------------
                when stopSCL =>
                    if counter = 24 then -- Wait 1/4 cycle before raising SDA
                        state <= stopSDA;
                    end if;
                
                when stopSDA =>
                    if counter = 24 then -- Wait 1/4 cycle before sending done signal
                        state <= waiting;
                    end if;
                ----------------------------------
            end case;
        end if;
    end process;

    -- Handles all logic within each state
    process(clk, rst)
    begin
        if rst = '1' then
            scl <= '1';
            sda <= '1';
            ackReady <= false;
            done <= false;
        elsif rising_edge(clk) then
            case state is
                when waiting =>
                    scl <= '1';
                    sda <= '1';
                    ackReady <= false;
                    done <= false;
                    
                ----------------------------------
                -- startSDA and startSCL write start bit
                ----------------------------------
                when startSDA =>
                    if counter < 49 then
                        counter <= counter + 1;
                    else
                        counter <= 0;
                        sda <= '0';
                    end if;
                    
                when startSCL =>
                    ackReady <= false;
                    if counter < 48 then  -- Only count to 48, because we transition to next state before adjusting SCL
                        counter <= counter + 1;
                    else
                        counter <= 0;
                    end if;
                ----------------------------------
                
                -- Hold SCL low for half a cycle
                when sclDown =>
                    scl <= '0';
                    sda <= byte(bitCounter-1);
                                       
                    if counter < 49 then
                        counter <= counter + 1;
                    else
                        counter <= 0;
                        bitCounter <= bitCounter - 1;
                    end if;
                    
                -- Hold SCL high for half a cycle
                when sclUp =>
                    scl <= '1';
                    if counter < 49 then
                        counter <= counter + 1;
                    else
                        counter <= 0;
                    end if;
                    
                -- Hold SCL low for half a cycle
                when waitForAck =>
                    scl <= '0';
                    if counter < 49 then
                        counter <= counter + 1;
                    else
                        ackReady <= true;
                        counter <= 0;
                    end if;
                    
                -- Hold SCL high for half a cycle, then read ACK
                when readAck =>
                    scl <= '1';
                    
                    bitCounter <= 8;
                    if counter < 49 then
                        counter <= counter + 1;
                    else
                        ackReady <= false;
                        counter <= 0;
                    end if;
                    
                -- Holds SCL and SDA low for half a cycle before sending a stop bit
                when lastLow =>
                    ackReady <= false;
                    scl <= '0';
                    sda <= '0';
                    if counter < 49 then
                        counter <= counter + 1;
                    else
                        counter <= 0;
                    end if;
                    
                -- Holds SCL high as a stop bit
                when stopSCL =>
                    scl <= '1';
                    if counter < 24 then
                        counter <= counter + 1;
                    else
                        counter <= 0;
                    end if;
                
                -- Holds SDA high as a stop bit
                when stopSDA =>
                    sda <= '1';
                    if counter < 24 then
                        counter <= counter + 1;
                    else
                        counter <= 0;
                        done <= true;
                    end if;
                
            end case;
        end if;
    end process;

end Behavioral;
