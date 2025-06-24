// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract WorkReport {
    // --- State Variables ---

    address public owner;
    mapping(address => bool) public isProjectLead;
    mapping(address => bool) public isContributor;

    // MODIFIED: Added 'isApproved' boolean to the Report struct
    struct Report {
        address reporter;
        string description;
        uint256 dollarValue;
        bool isApproved; // This will default to false
    }

    Report[] public reports;

    // --- Events ---

    event ProjectLeadAdded(address indexed user);
    event ProjectLeadRemoved(address indexed user);
    event ContributorAdded(address indexed user);
    event ContributorRemoved(address indexed user);
    event ReportSubmitted(address indexed reporter, uint256 reportId, string description);
    // NEW: Event for when a report's approval status is changed
    event ReportApprovalSet(uint256 indexed reportId, address indexed approver, bool isApproved);

    // --- Modifiers ---

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the owner");
        _;
    }

    modifier onlyProjectLead() {
        require(isProjectLead[msg.sender], "Not a project lead");
        _;
    }

    modifier onlyContributor() {
        require(isContributor[msg.sender], "Not a contributor");
        _;
    }

    // --- Functions ---

    constructor() {
        owner = msg.sender;
        isProjectLead[msg.sender] = true;
        emit ProjectLeadAdded(msg.sender);
    }

    // ... (addProjectLead, removeProjectLead, addContributor, removeContributor functions remain the same) ...
    function addProjectLead(address _user) public onlyOwner {
        require(!isProjectLead[_user], "User is already a project lead");
        isProjectLead[_user] = true;
        emit ProjectLeadAdded(_user);
    }

    function removeProjectLead(address _user) public onlyOwner {
        require(isProjectLead[_user], "User is not a project lead");
        isProjectLead[_user] = false;
        emit ProjectLeadRemoved(_user);
    }

    function addContributor(address _user) public onlyProjectLead {
        require(!isContributor[_user], "User is already a contributor");
        isContributor[_user] = true;
        emit ContributorAdded(_user);
    }

    function removeContributor(address _user) public onlyProjectLead {
        require(isContributor[_user], "User is not a contributor");
        isContributor[_user] = false;
        emit ContributorRemoved(_user);
    }

    /**
     * @notice Allows a contributor to submit a work report.
     * The 'isApproved' flag is automatically set to false.
     */
    function submitReport(string memory _description, uint256 _dollarValue) public onlyContributor {
        uint256 reportId = reports.length;
        // MODIFIED: We now add 'false' for the isApproved field when creating the report.
        reports.push(Report(msg.sender, _description, _dollarValue, false));
        emit ReportSubmitted(msg.sender, reportId, _description);
    }

    /**
     * @notice Sets the approval status of a report. Can only be called by a project lead.
     * @param _reportId The ID (index) of the report to modify.
     * @param _isApproved The new approval status (true or false).
     */
    function setReportApproval(uint256 _reportId, bool _isApproved) public onlyProjectLead {
        require(_reportId < reports.length, "Invalid report ID");

        // Directly modify the report in storage
        reports[_reportId].isApproved = _isApproved;

        emit ReportApprovalSet(_reportId, msg.sender, _isApproved);
    }
}