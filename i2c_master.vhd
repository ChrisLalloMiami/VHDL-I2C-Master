-- Implementation of the I2C protocol.
-- Note: Clocking wizard pulls system clock down to 100 MHz for locking with other slaves.


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;


entity i2c_master is
    generic(
        MASTER_CLK : integer := 100000000; -- Clocking wizard runs clock at 100 MHz
        TARGET_CLK : integer := 1000000    -- Run SCL at common 1 MHz
    );
    
    port (
        clk    : in std_logic;
        rst    : in std_logic;
        scl    : out std_logic;
        sda    : inout std_logic
    );
end i2c_master;

architecture Behavioral of i2c_master is

    type state_type is (setup, send, waitForAck, readAck, pause, idle);
    signal state               : state_type;
    
    constant TOTAL             : integer                       := MASTER_CLK/TARGET_CLK;
    constant HALF              : integer                       := TOTAL / 2;
    
    signal ack                 : std_logic; -- Acknowledge signal from slave
    signal sda_out             : std_logic; -- Used for actual SDA IO (rather than SDA pin)
    signal sda_tristate_enable : std_logic; -- Tristate IO switch. '0' for write, '1' for read
    
    signal new_clk             : std_logic; -- 100 MHz clock produced by clocking wizard
    signal clk_lock            : std_logic;
    
    -- Temporary test values
    constant message           : std_logic_vector(15 downto 0) := "1100110010101010";
    constant numBytes          : integer                       := 2;
    constant slaveAddress      : std_logic_vector(7 downto 0)  := "11111110";

    signal byte                : std_logic_vector(7 downto 0)  := (others => '0');
    signal enable              : std_logic                     := '0';
    signal sendStartBit        : boolean                       := false;
    signal sendStopBit         : boolean                       := false;
    signal ackReady            : boolean;
    signal done                : boolean;
    signal setTristate         : boolean                       := false;
    
    signal byteCounter         : integer                       := numBytes; -- Current byte being sent
    signal counter             : integer                       := 0;
    
    ----------------------------------------------------------------
    -- Clocking wizard to match master and slave clocks
    component clk_wiz_0 is
        port(
            reset    : in std_logic;
            clk_in1  : in std_logic;
            clk_out1 : out std_logic;
            locked   : out std_logic
        );
    end component;
    ----------------------------------------------------------------

    ----------------------------------------------------------------
    -- IOBuffer for SDA IO pin
    component IOBUF
        port (
            O  : out std_logic;
            I  : in std_logic;
            IO : inout std_logic;
            T  : in std_logic
        );
    end component;
    ----------------------------------------------------------------

    ----------------------------------------------------------------
    -- Data Sender for sending message bytes to slave
    component i2c_dataSender
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
    end component;
begin
    ----------------------------------------------------------------
    -- Map signals to IOBuffer
    IOBUF_sda : IOBUF
    port map (
        O   =>  ack,
        I   =>  sda_out,
        IO  =>  sda,
        T   =>  sda_tristate_enable        
    );
    ----------------------------------------------------------------
    
    ----------------------------------------------------------------
    -- Map signals to clocking wizard
    clk_maker : clk_wiz_0
        port map(
            reset     => rst,
            clk_in1   => clk,
            clk_out1  => new_clk,
            locked    => clk_lock
        );
    ----------------------------------------------------------------
    
    ----------------------------------------------------------------
    -- Map signals to dataSender
    dataSender_comp : i2c_dataSender
        port map (
            clk          => new_clk,
            rst          => rst,
                      
            sda          => sda_out,
            scl          => scl,
            
            byte         => byte,
            enable       => enable,
            sendStartBit => sendStartBit,
            sendStopBit  => sendStopBit,
            ackReady     => ackReady,
            done         => done,
            setTristate  => setTristate
        );
        ----------------------------------------------------------------
    
     -- Handles all state transitions
    process(new_clk, rst)
    begin
        if rst = '1' then
            state <= setup;
        elsif rising_edge(new_clk) then
            case state is
                -- Sets up each byte for sending
                when setup =>
                    state <= send;
                
                -- Triggers data sending  
                when send =>
                    state <= waitForAck;
                
                -- Waits for ackReady to go high before adjusting tristate and reading ACK
                when waitForAck =>
                    if ackReady then
                        state <= readAck;
                    end if;
                    
                
                when readAck =>
--                    if ack = '0' then
                        state <= pause;
--                    end if;
                    
                
                when pause =>
                    if counter = 47 then
                        if byteCounter <= 0 then
                            state <= idle;
                        else
                            state <= setup;
                        end if;
                    end if;
                
                
                when idle =>
                    
                
            end case;
        end if;
    end process;
    
    -- Handles all logic within each state
    process(new_clk, rst)
    begin
        if rst = '1' then
            enable <= '0';
        elsif rising_edge(new_clk) then
            case state is
                -- Sets up each byte for sending
                when setup =>
                    sda_tristate_enable <= '0';
                    byte <= message((8 * byteCounter) - 1 downto (8 * byteCounter) - 8);
                    
                    if byteCounter = numBytes then
                        sendStartBit <= true;
                    else
                        sendStartBit <= false;
                    end if;
                    
                    if byteCounter = 1 then
                        sendStopBit <= true;
                    else
                        sendStopBit <= false;
                    end if;
                
                -- Triggers data sending
                when send =>
                    enable <= '1';
                
                -- Waits for ackReady to go high before adjusting tristate and reading ACK
                when waitForAck =>
                    if setTristate then
                        sda_tristate_enable <= '1';
                    end if;
                    
                
                when readAck =>
                    sda_tristate_enable <= '0';
                   if ack = '0' then
                        byteCounter <= byteCounter - 1;        
                   end if;
                    
                    
                when pause =>
                    if counter < 47 then
                        counter <= counter + 1;
                    else
                        enable <= '0';
                        counter <= 0;
                    end if;
                    
                    
                when idle =>
                    enable <= '0';
            end case;
        end if;
    
    end process;
    

end Behavioral;
