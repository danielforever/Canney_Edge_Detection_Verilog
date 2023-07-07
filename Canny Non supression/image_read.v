`include "parameter.v" 						// Include definition file
module image_read
#(
  parameter WIDTH 	= 768, 					// Image width
			HEIGHT 	= 512, 						// Image height
			//INFILE  = "better_gray_scale_output.hex", 	// image file
			INFILE  = "gussian_filter_output.hex",
			START_UP_DELAY = 100, 				// Delay during start up time
			HSYNC_DELAY = 160,					// Delay between HSYNC pulses	
			VALUE= 100,								// value for Brightness operation
			THRESHOLD= 90,							// Threshold value for Threshold operation
			SIGN=0									// Sign value using for brightness operation
														// SIGN = 0: Brightness subtraction
														// SIGN = 1: Brightness addition
)
(
	input HCLK,										// clock					
	input HRESETn,									// Reset (active low)
	output VSYNC,								// Vertical synchronous pulse
	// This signal is often a way to indicate that one entire image is transmitted.
	// Just create and is not used, will be used once a video or many images are transmitted.
	output reg HSYNC,								// Horizontal synchronous pulse
	// An HSYNC indicates that one line of the image is transmitted.
	// Used to be a horizontal synchronous signals for writing bmp file.
    output reg [7:0]  DATA_R0,				// 8 bit Red data (even)
    output reg [7:0]  DATA_G0,				// 8 bit Green data (even)
    output reg [7:0]  DATA_B0,				// 8 bit Blue data (even)
    output reg [7:0]  DATA_R1,				// 8 bit Red  data (odd)
    output reg [7:0]  DATA_G1,				// 8 bit Green data (odd)
    output reg [7:0]  DATA_B1,				// 8 bit Blue data (odd)
	output			  ctrl_done					// Done flag
);			
//-------------------------------------------------
// Internal Signals
//-------------------------------------------------

parameter sizeOfWidth = 8;						// data width
parameter sizeOfLengthReal = 1179648; 		// image data : 1179648 bytes: 512 * 768 *3 
// local parameters for FSM
localparam		ST_IDLE 	= 2'b00,		// idle state
				ST_VSYNC	= 2'b01,			// state for creating vsync 
				ST_HSYNC	= 2'b10,			// state for creating hsync 
				ST_DATA		= 2'b11;		// state for data processing 
reg [1:0] cstate, 						// current state
		  nstate;							// next state			
reg start;									// start signal: trigger Finite state machine beginning to operate
reg HRESETn_d;								// delayed reset signal: use to create start signal
reg 		ctrl_vsync_run; 				// control signal for vsync counter  
reg [8:0]	ctrl_vsync_cnt;			// counter for vsync
reg 		ctrl_hsync_run;				// control signal for hsync counter
reg [8:0]	ctrl_hsync_cnt;			// counter  for hsync
reg 		ctrl_data_run;					// control signal for data processing
reg [31 : 0]  in_memory    [0 : sizeOfLengthReal/4]; 	// memory to store  32-bit data image
reg [7 : 0]   total_memory [0 : sizeOfLengthReal-1];	// memory to store  8-bit data image
// temporary memory to save image data : size will be WIDTH*HEIGHT*3
integer temp_BMP   [0 : WIDTH*HEIGHT*3 - 1];			
integer org_R  [0 : WIDTH*HEIGHT - 1]; 	// temporary storage for R component
integer org_G  [0 : WIDTH*HEIGHT - 1];	// temporary storage for G component
integer org_B  [0 : WIDTH*HEIGHT - 1];	// temporary storage for B component
// counting variables
integer i, j;
// temporary signals for calculation: details in the paper.
integer tempR0,tempR1,tempG0,tempG1,tempB0,tempB1; // temporary variables in contrast and brightness operation

integer value,value1,value2,value4;// temporary variables in invert and threshold operation
integer sobel00,sobel01,sobel02;
integer sobel10,sobel11,sobel12;
integer sobel20,sobel21,sobel22;
integer gx,gy,tan_out,flag;
reg signed [15:0] g;
reg [ 9:0] row; // row index of the image
reg [10:0] col; // column index of the image
reg [18:0] data_count; // data counting for entire pixels of the image


//-------------------------------------------------//
// -------- Reading data from input file ----------//
//-------------------------------------------------//
initial begin
    $readmemh(INFILE,total_memory,0,sizeOfLengthReal-1); // read file from INFILE
end
// use 3 intermediate signals RGB to save image data
always@(start) begin
    $display("read input");
    if(start == 1'b1) begin
        for(i=0; i<WIDTH*HEIGHT*3 ; i=i+1) begin
            temp_BMP[i] = total_memory[i+0][7:0]; 
        end
        
        for(i=0; i<HEIGHT; i=i+1) begin
            for(j=0; j<WIDTH; j=j+1) begin
                org_R[WIDTH*i+j] = temp_BMP[WIDTH*3*(HEIGHT-i-1)+3*j+0]; // save Red component
                org_G[WIDTH*i+j] = temp_BMP[WIDTH*3*(HEIGHT-i-1)+3*j+1];// save Green component
                org_B[WIDTH*i+j] = temp_BMP[WIDTH*3*(HEIGHT-i-1)+3*j+2];// save Blue component
            end
        end
    end
end
//----------------------------------------------------//
// ---Begin to read image file once reset was high ---//
// ---by creating a starting pulse (start)------------//
//----------------------------------------------------//
always@(posedge HCLK, negedge HRESETn)
begin
    if(!HRESETn) begin
        start <= 0;
		HRESETn_d <= 0;
    end
    else begin											//        		______ 				
        HRESETn_d <= HRESETn;							//       	|		|
		if(HRESETn == 1'b1 && HRESETn_d == 1'b0)		// __0___|	1	|___0____	: starting pulse
			start <= 1'b1;
		else
			start <= 1'b0;
    end
end

//-----------------------------------------------------------------------------------------------//
// Finite state machine for reading RGB888 data from memory and creating hsync and vsync pulses --//
//-----------------------------------------------------------------------------------------------//
always@(posedge HCLK, negedge HRESETn)
begin
    if(~HRESETn) begin
        cstate <= ST_IDLE;
    end
    else begin
        cstate <= nstate; // update next state 
    end
end
//-----------------------------------------//
//--------- State Transition --------------//
//-----------------------------------------//
// IDLE . VSYNC . HSYNC . DATA
always @(*) begin
	case(cstate)
		ST_IDLE: begin
			if(start)
				nstate = ST_VSYNC;
			else
				nstate = ST_IDLE;
		end			
		ST_VSYNC: begin
			if(ctrl_vsync_cnt == START_UP_DELAY) 
				nstate = ST_HSYNC;
			else
				nstate = ST_VSYNC;
		end
		ST_HSYNC: begin
			if(ctrl_hsync_cnt == HSYNC_DELAY) 
				nstate = ST_DATA;
			else
				nstate = ST_HSYNC;
		end		
		ST_DATA: begin
			if(ctrl_done)
				nstate = ST_IDLE;
			else begin
				if(col == WIDTH - 2)
					nstate = ST_HSYNC;
				else
					nstate = ST_DATA;
			end
		end
	endcase
end
// ------------------------------------------------------------------- //
// --- counting for time period of vsync, hsync, data processing ----  //
// ------------------------------------------------------------------- //
always @(*) begin
	ctrl_vsync_run = 0;
	ctrl_hsync_run = 0;
	ctrl_data_run  = 0;
	case(cstate)
		ST_VSYNC: 	begin ctrl_vsync_run = 1; end 	// trigger counting for vsync
		ST_HSYNC: 	begin ctrl_hsync_run = 1; end	// trigger counting for hsync
		ST_DATA: 	begin ctrl_data_run  = 1; end	// trigger counting for data processing
	endcase
end
// counters for vsync, hsync
always@(posedge HCLK, negedge HRESETn)
begin
    if(~HRESETn) begin
        ctrl_vsync_cnt <= 0;
		ctrl_hsync_cnt <= 0;
    end
    else begin
        if(ctrl_vsync_run)
			ctrl_vsync_cnt <= ctrl_vsync_cnt + 1; // counting for vsync
		else 
			ctrl_vsync_cnt <= 0;
			
        if(ctrl_hsync_run)
			ctrl_hsync_cnt <= ctrl_hsync_cnt + 1;	// counting for hsync		
		else
			ctrl_hsync_cnt <= 0;
    end
end
// counting column and row index  for reading memory 
always@(posedge HCLK, negedge HRESETn)
begin
    if(~HRESETn) begin
        row <= 0;
		col <= 0;
    end
	else begin
		if(ctrl_data_run) begin
			if(col == WIDTH - 2) begin
				row <= row + 1;
			end
			if(col == WIDTH - 2) 
				col <= 0;
			else 
				col <= col + 2; // reading 2 pixels in parallel
		end
	end
end
//-------------------------------------------------//
//----------------Data counting---------- ---------//
//-------------------------------------------------//
always@(posedge HCLK, negedge HRESETn)
begin
    if(~HRESETn) begin
        data_count <= 0;
    end
    else begin
        if(ctrl_data_run)
			data_count <= data_count + 1;
    end
end
assign VSYNC = ctrl_vsync_run;
assign ctrl_done = (data_count == 196607)? 1'b1: 1'b0; // done flag
//-------------------------------------------------//
//-------------  Image processing   ---------------//
//-------------------------------------------------//
always @(*) begin
	
	HSYNC   = 1'b0;
	DATA_R0 = 0;
	DATA_G0 = 0;
	DATA_B0 = 0;                                       
	DATA_R1 = 0;
	DATA_G1 = 0;
	DATA_B1 = 0;                                         
	if(ctrl_data_run) begin
		
		HSYNC   = 1'b1;
		`ifdef SOBEL_OPERATION
		  //----- role one ----//	
		  flag = 0;	  
		  if( row - 1 < 0 || row - 1 > HEIGHT || col - 1 < 0 || col - 1 > WIDTH ) begin
		      sobel00 = 0;
          end
          else begin
              sobel00 = org_R[WIDTH * (row - 1) + col - 1];
          end	
          
          if( row - 1 < 0 || row - 1 > HEIGHT || col < 0 || col > WIDTH ) begin
		      sobel01 = 0;
          end
          else begin
              sobel01 = org_R[WIDTH * (row - 1) + col];
          end	
          	      
          if( row - 1 < 0 || row - 1 > HEIGHT || col + 1 < 0 || col + 1 > WIDTH ) begin
		      sobel02 = 0;
          end
          else begin
              sobel02 = org_R[WIDTH * (row - 1) + col + 1];
          end	          	 	
          //----- role two ----//
		  if( row < 0 || row > HEIGHT || col - 1 < 0 || col - 1 > WIDTH ) begin
		      sobel10 = 0;
          end
          else begin
              sobel10 = org_R[WIDTH * row + col - 1];
          end	
          
          if( row < 0 || row > HEIGHT || col < 0 || col > WIDTH ) begin
		      sobel11 = 0;
          end
          else begin
              sobel11 = org_R[WIDTH * row + col];
          end	
          	      
          if( row < 0 || row > HEIGHT || col + 1 < 0 || col + 1 > WIDTH ) begin
		      sobel12 = 0;
          end
          else begin
              sobel12 = org_R[WIDTH * row + col + 1];
          end	          	 	
          //----- role three ----//
		  if( row + 1 < 0 || row + 1 > HEIGHT || col - 1 < 0 || col - 1 > WIDTH ) begin
		      sobel20 = 0;
          end
          else begin
              sobel20 = org_R[WIDTH * (row + 1) + col - 1];
          end	
          
          if( row + 1 < 0 || row + 1 > HEIGHT || col < 0 || col > WIDTH) begin
		      sobel21 = 0;
          end
          else begin
              sobel21 = org_R[WIDTH * (row + 1) + col];
          end	
          	      
          if( row + 1 < 0 || row + 1 > HEIGHT || col + 1 < 0 || col + 1 > WIDTH) begin
		      sobel22 = 0;
          end
          else begin
              sobel22 = org_R[WIDTH * (row + 1) + col + 1];
          end
          
          gx = sobel02 + 2 * sobel12 + sobel22 - sobel00 - 2 * sobel10 - sobel20;
          gy = sobel00 + 2 * sobel01 + sobel02 - sobel20 - 2 * sobel21 - sobel22;
          g = gx * gx + gy * gy;
          tan_out = ($atan2(gy,gx) * 7.0 / 22.0 * 180);
          //$display(tan_out);
          g = $sqrt(g);
          if ( (0 < tan_out && tan_out < 22.5) || (157.5 <= tan_out && tan_out <= 180) ) begin
            //$display("check");
            $display(tan_out);
            
            flag = 1;
          end
          //if ( tan_out == 0) begin
          //  flag = 2;
          //end 
          
          if (g > 255) begin
            DATA_R0 <= 255;
            DATA_G0 <= 255;
            DATA_B0 <= 255;
          end
          else begin
            DATA_R0 <= g;
            DATA_G0 <= g;
            DATA_B0 <= g;

          end
//**************** Another pixel *****************************//  
          
          col = col + 1;        
		  if( row - 1 < 0 || row - 1 > HEIGHT || col - 1 < 0 || col - 1 > WIDTH ) begin
		      sobel00 = 0;
          end
          else begin
              sobel00 = org_R[WIDTH * (row - 1) + col - 1];
          end	
          
          if( row - 1 < 0 || row - 1 > HEIGHT || col < 0 || col > WIDTH ) begin
		      sobel01 = 0;
          end
          else begin
              sobel01 = org_R[WIDTH * (row - 1) + col];
          end	
          	      
          if( row - 1 < 0 || row - 1 > HEIGHT || col + 1 < 0 || col + 1 > WIDTH ) begin
		      sobel02 = 0;
          end
          else begin
              sobel02 = org_R[WIDTH * (row - 1) + col + 1];
          end	          	 	
          //----- role two ----//
		  if( row < 0 || row > HEIGHT || col - 1 < 0 || col - 1 > WIDTH ) begin
		      sobel10 = 0;
          end
          else begin
              sobel10 = org_R[WIDTH * row + col - 1];
          end	
          
          if( row < 0 || row > HEIGHT || col < 0 || col > WIDTH ) begin
		      sobel11 = 0;
          end
          else begin
              sobel11 = org_R[WIDTH * row + col];
          end	
          	      
          if( row < 0 || row > HEIGHT || col + 1 < 0 || col + 1 > WIDTH ) begin
		      sobel12 = 0;
          end
          else begin
              sobel12 = org_R[WIDTH * row + col + 1];
          end	          	 	
          //----- role three ----//
		  if( row + 1 < 0 || row + 1 > HEIGHT || col - 1 < 0 || col - 1 > WIDTH ) begin
		      sobel20 = 0;
          end
          else begin
              sobel20 = org_R[WIDTH * (row + 1) + col - 1];
          end	
          
          if( row + 1 < 0 || row + 1 > HEIGHT || col < 0 || col > WIDTH) begin
		      sobel21 = 0;
          end
          else begin
              sobel21 = org_R[WIDTH * (row + 1) + col];
          end	
          	      
          if( row + 1 < 0 || row + 1 > HEIGHT || col + 1 < 0 || col + 1 > WIDTH) begin
		      sobel22 = 0;
          end
          else begin
              sobel22 = org_R[WIDTH * (row + 1) + col + 1];
          end
          
          gx = sobel02 + 2 * sobel12 + sobel22 - sobel00 - 2 * sobel10 - sobel20;
          gy = sobel00 + 2 * sobel01 + sobel02 - sobel20 - 2 * sobel21 - sobel22;
          
          g = gx * gx + gy * gy;
          g = $sqrt(g);
          tan_out = $atan2(gy,gx);
          if( flag == 1 ) begin
            DATA_R1 <= 0;
            DATA_G1 <= 0;
            DATA_B1 <= 0;
          end
          else if (g > 255*255) begin
            $display(tan_out * 7.0 / 22.0 * 180);
            DATA_R1 <= 255;
            DATA_G1 <= 255;
            DATA_B1 <= 255;
          end 
          else begin
            DATA_R1 <= g;
            DATA_G1 <= g;
            DATA_B1 <= g;
          end
          col = col - 1;
          flag = 0;
		`endif
		
	end
end

endmodule

//integer sobel00,sobel01,sobel02;
//integer sobel10,sobel11,sobel12;
//integer sobel20,sobel21,sobel22;
