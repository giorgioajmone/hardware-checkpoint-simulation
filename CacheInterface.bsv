// SINGLE CORE CACHE INTERFACE WITH NO PPP
import MainMem::*;
import MemTypes::*;
import Cache32::*;
import Cache32d::*;
import Cache512::*;
import Vector::*;
import FIFOF::*;
import SpecialFIFOs::*;

import SnapshotTypes::*;

interface CacheInterface;
    method Action sendReqData(CacheReq req);
    method ActionValue#(Word) getRespData();
    method Action sendReqInstr(CacheReq req);
    method ActionValue#(Word) getRespInstr();

    // INSTRUMENTATION 
    method Action halt;
    method Action canonicalize;
    method Action restart;
    method Action halted;
    method Action restarted;
    method Action canonicalized;

    method Action request(SnapshotRequestType operation, ComponentdId id, ExchageAddress addr, ExchangeData data);
    method ActionValue#(ExchangeData) response(ComponentdId id);

endinterface

typedef enum {
    INSTR,
    DATA
} CacheInterfaceRR deriving (Eq, FShow, Bits);

module mkCacheInterface(CacheInterface);
    let verbose = False;
    MainMem mainMem <- mkMainMem(); 
    Cache512 cacheL2 <- mkCache512;
    Cache32 cacheI <- mkCache32;
    Cache32d cacheD <- mkCache32d;

    // You need to add rules and/or state elements.

    FIFOF#(MainMemReq) iToL2 <- mkBypassFIFOF;
    FIFOF#(MainMemReq) dToL2 <- mkBypassFIFOF;
    Reg#(CacheInterfaceRR) toL2RoundRobin <- mkReg(INSTR);

    Reg#(Bool) outstandingMiss <- mkReg(False);

    Reg#(Bool) is_canonicalizing <- mkReg(False);
    Reg#(Bool) is_canonicalized <- mkReg(False);

    rule getFromMem;
        let resp <- mainMem.get();
        if (verbose) $display("CacheInterface: Getting from Mem");
        cacheL2.putFromMem(resp);
    endrule
    
    rule sendToMem;
        let req <- cacheL2.getToMem();
        if (verbose) $display("CacheInterface: Sending to Mem");
        mainMem.put(req);
    endrule
    
    rule getFromL2;
        let resp <- cacheL2.getToProc();
        if (verbose) $display("CacheInterface: Getting from L2");
        if (toL2RoundRobin == INSTR) begin
            cacheD.putFromMem(resp);
        end else begin
            cacheI.putFromMem(resp);
        end
        outstandingMiss <= False;
    endrule
    
    rule sendToL2 if (outstandingMiss == False);
        let req;
        if (toL2RoundRobin == INSTR && iToL2.notEmpty) begin
            req = iToL2.first;
            iToL2.deq;
            if (verbose) $display("CacheInterface: Sending from L1i to L2");
            cacheL2.putFromProc(req);
            toL2RoundRobin <= DATA;
            outstandingMiss <= True;
        end else if (toL2RoundRobin == DATA && dToL2.notEmpty) begin
            req = dToL2.first;
            dToL2.deq;
            if (verbose) $display("CacheInterface: Sending from L1d to L2");
            cacheL2.putFromProc(req);
            toL2RoundRobin <= INSTR;
            outstandingMiss <= True;
        end else if (toL2RoundRobin == INSTR && dToL2.notEmpty) begin
            req = dToL2.first;
            dToL2.deq;
            if (verbose) $display("CacheInterface: Sending from L1d to L2");
            cacheL2.putFromProc(req);
            toL2RoundRobin <= INSTR;
            outstandingMiss <= True;
        end else if (toL2RoundRobin == DATA && iToL2.notEmpty) begin
            req = iToL2.first;
            iToL2.deq;
            if (verbose) $display("CacheInterface: Sending from L1i to L2");
            cacheL2.putFromProc(req);
            toL2RoundRobin <= DATA;
            outstandingMiss <= True;
        end
    endrule 

    rule toL2Data;
        let req <- cacheD.getToMem();
        dToL2.enq(req);
    endrule

    rule toL2Instr;
        let req <- cacheI.getToMem();
        iToL2.enq(req);
    endrule

    rule check_canonicalization if (is_canonicalizing && !is_canonicalized && !iToL2.notEmpty && !dToL2.notEmpty);
        // Check:
        // 1. All components (L1i, L1d, L2, DRAM) are canonicalized
        // 2. Two FIFOs (iToL2, dToL2) are empty
        mainMem.canonicalized;
        cacheL2.canonicalized;
        cacheI.canonicalized;
        cacheD.canonicalized;

        is_canonicalized <= True;
    endrule

    method Action halt;
        is_canonicalizing <= True;
        mainMem.halt;
        cacheL2.halt;
        cacheI.halt;
        cacheD.halt;
    endmethod

    method Action canonicalize;
        is_canonicalized <= True;
        mainMem.halt;
        cacheL2.halt;
        cacheI.halt;
        cacheD.halt;
    endmethod

    method Action restart;
        is_canonicalizing <= False;
        is_canonicalized <= False;
    endmethod

    method Action halted if (is_canonicalizing || is_canonicalized);
    endmethod

    method Action restarted if (!is_canonicalizing && !is_canonicalized);
    endmethod

    method Action canonicalized if (is_canonicalized);
    endmethod

    method Action request(SnapshotRequestType operation, ComponentdId id, ExchageAddress addr, ExchangeData data);
        // FIXME: I haven't find a better way to translate the compoment ID to the actual component. 
        // Now we have fixed the assignment of the component ID to the actual component.
        // But, we may want to change the assignment in the future.
        case (id)
            1: cacheI.request(operation, id, addr, data);
            2: cacheD.request(operation, id, addr, data);
            3: cacheL2.request(operation, id, addr, data);
            4: mainMem.request(operation, id, addr, data);
            default: $display("CacheInterface: Invalid component ID");
        endcase
    endmethod

    method ActionValue#(ExchangeData) response(ComponentdId id);
        case (id)
            1: begin
                let data <- cacheI.response(id);
                return data;
            end
            2: begin
                let data <- cacheD.response(id);
                return data;
            end
            3: begin 
                let data <- cacheL2.response(id);
                return data;
            end
            4: begin 
                let data <- mainMem.response(id);
                return data;
            end
            default: begin 
                $display("CacheInterface: Invalid component ID");
                return signExtend(1'b1);
            end
        endcase
    endmethod

    method Action sendReqData(CacheReq req) if (!is_canonicalizing && !is_canonicalized);
        cacheD.putFromProc(req);
    endmethod

    method ActionValue#(Word) getRespData() if(!is_canonicalized);
        let resp <- cacheD.getToProc();
        return resp;
    endmethod


    method Action sendReqInstr(CacheReq req) if (!is_canonicalizing && !is_canonicalized);
        cacheI.putFromProc(req);
    endmethod

    method ActionValue#(Word) getRespInstr() if(!is_canonicalized);
        let resp <- cacheI.getToProc();
        return resp;
    endmethod
endmodule
