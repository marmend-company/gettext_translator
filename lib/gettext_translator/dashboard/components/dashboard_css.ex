defmodule GettextTranslator.Dashboard.Components.GettextDashboardCSS do
  @moduledoc """
  Provides CSS styles for the Gettext Translator Dashboard that match
  Phoenix LiveDashboard's look and feel.
  """

  def styles do
    """
    /* Dashboard Container */
    .dashboard-container {
      padding: 1rem;
    }

    /* Card styles - matches LiveDashboard */
    .dashboard-card {
      background-color: #fff;
      border-radius: 0.5rem;
      box-shadow: 0 1px 3px rgba(0, 0, 0, 0.12);
      margin-bottom: 1rem;
      padding: 1rem;
    }

    .card-title {
      color: #333;
      font-size: 1.25rem;
      font-weight: 600;
      margin-bottom: 1rem;
    }

    .card-title-container {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 1rem;
    }

    /* Stats container */
    .dashboard-stats-container {
      display: flex;
      flex-wrap: wrap;
      justify-content: space-between;
      align-items: center;
      gap: 1rem;
    }

    .dashboard-stat {
      display: flex;
      flex-direction: column;
      margin-right: 2rem;
    }

    .dashboard-stat-label {
      color: #666;
      font-size: 0.875rem;
    }

    .dashboard-stat-value {
      font-size: 1rem;
      font-weight: 500;
    }

    .dashboard-controls-container {
      display: flex;
      gap: 0.5rem;
      margin-left: auto;
    }

    /* Table styles */
    .dashboard-table-container {
      overflow-x: auto;
    }

    .table {
      width: 100%;
      margin-bottom: 1rem;
      color: #212529;
      border-collapse: collapse;
    }

    .table th,
    .table td {
      padding: 0.75rem;
      vertical-align: top;
      border-top: 1px solid #dee2e6;
    }

    .table thead th {
      vertical-align: bottom;
      border-bottom: 2px solid #dee2e6;
      font-weight: 600;
      text-align: left;
    }

    .table-striped tbody tr:nth-of-type(odd) {
      background-color: rgba(0, 0, 0, 0.05);
    }

    .table-hover tbody tr:hover {
      background-color: rgba(0, 0, 0, 0.075);
    }

    /* Message ID cell */
    .message-id-cell {
      font-family: monospace;
      font-size: 0.875rem;
      max-width: 20rem;
    }

    .message-id {
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
      width: 100%;
    }

    .plural-id {
      color: #6c757d;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
      width: 100%;
      margin-top: 0.25rem;
    }

    /* Translation cell */
    .translation-cell {
      font-family: monospace;
      font-size: 0.875rem;
    }

    .translation-content {
      word-break: break-all;
    }

    .plural-translation {
      color: #6c757d;
      margin-top: 0.5rem;
    }

    /* Buttons */
    .btn {
      display: inline-block;
      font-weight: 400;
      text-align: center;
      vertical-align: middle;
      user-select: none;
      border: 1px solid transparent;
      padding: 0.375rem 0.75rem;
      font-size: 0.875rem;
      line-height: 1.5;
      border-radius: 0.25rem;
      transition: color 0.15s, background-color 0.15s, border-color 0.15s;
      cursor: pointer;
    }

    .btn-primary {
      background-color: #3490dc;
      color: white;
    }

    .btn-primary:hover {
      background-color: #2779bd;
    }

    .btn-success {
      background-color: #38c172;
      color: white;
    }

    .btn-success:hover {
      background-color: #2d995b;
    }

    .btn-secondary {
      background-color: #6c757d;
      color: white;
    }

    .btn-secondary:hover {
      background-color: #5a6268;
    }

    .btn-link {
      font-weight: 400;
      color: #3490dc;
      text-decoration: none;
      background-color: transparent;
      border: none;
      padding: 0;
    }

    .btn-link:hover {
      color: #1d68a7;
      text-decoration: underline;
    }

    .btn-sm {
      padding: 0.25rem 0.5rem;
      font-size: 0.75rem;
    }

    /* Status badges */
    .badge {
      display: inline-block;
      padding: 0.35em 0.65em;
      font-size: 0.75em;
      font-weight: 700;
      line-height: 1;
      text-align: center;
      white-space: nowrap;
      vertical-align: baseline;
      border-radius: 0.25rem;
    }

    .bg-warning {
      background-color: #ffc107;
    }

    .bg-success {
      background-color: #28a745;
      color: white;
    }

    .bg-info {
      background-color: #17a2b8;
      color: white;
    }

    .text-warning {
      color: #ffc107;
    }

    .text-success {
      color: #28a745;
    }

    .text-danger {
      color: #dc3545;
    }

    .text-muted {
      color: #6c757d;
    }

    .small {
      font-size: 0.875em;
    }

    .fw-semibold {
      font-weight: 600;
    }

    /* Forms */
    .translation-form {
      display: flex;
      flex-direction: column;
      gap: 0.75rem;
    }

    .form-group {
      margin-bottom: 0.5rem;
    }

    .form-label {
      display: block;
      margin-bottom: 0.25rem;
      font-size: 0.875rem;
      font-weight: 500;
    }

    .form-control {
      display: block;
      width: 100%;
      padding: 0.375rem 0.75rem;
      font-size: 0.875rem;
      line-height: 1.5;
      color: #495057;
      background-color: #fff;
      background-clip: padding-box;
      border: 1px solid #ced4da;
      border-radius: 0.25rem;
      transition: border-color 0.15s;
    }

    .form-control:focus {
      border-color: #80bdff;
      outline: 0;
      box-shadow: 0 0 0 0.2rem rgba(0, 123, 255, 0.25);
    }

    .form-actions {
      display: flex;
      justify-content: flex-end;
      gap: 0.5rem;
      margin-top: 0.75rem;
    }

    .align-middle {
      vertical-align: middle !important;
    }

    .mt-4 {
      margin-top: 1.5rem;
    }

    .mt-1 {
      margin-top: 0.25rem;
    }

    /* LLM Provider Info */
    .llm-provider-info {
      display: flex;
      align-items: center;
      gap: 0.5rem;
      padding: 0.5rem 0.75rem;
      margin-bottom: 1rem;
      background-color: #e8f4fd;
      border: 1px solid #b8daff;
      border-radius: 0.25rem;
      font-size: 0.875rem;
    }

    .llm-provider-label {
      font-weight: 600;
      color: #004085;
    }

    .llm-provider-value {
      color: #004085;
    }

    /* LLM Translate Form */
    .translation-edit-container {
      display: flex;
      flex-direction: column;
      gap: 0.75rem;
    }

    .llm-translate-form {
      border-top: 1px solid #dee2e6;
      padding-top: 0.75rem;
    }

    /* Info button style */
    .btn-info {
      background-color: #17a2b8;
      color: white;
      border-color: #17a2b8;
    }

    .btn-info:hover {
      background-color: #138496;
      border-color: #117a8b;
    }

    .btn-info:disabled {
      background-color: #17a2b8;
      opacity: 0.65;
      cursor: not-allowed;
    }

    /* Tab Navigation */
    .tab-nav {
      display: flex;
      border-bottom: 2px solid #dee2e6;
      margin-bottom: 1rem;
    }

    .tab-nav-item {
      padding: 0.5rem 1rem;
      border: none;
      background: transparent;
      color: #6c757d;
      font-size: 0.875rem;
      font-weight: 500;
      cursor: pointer;
      border-bottom: 2px solid transparent;
      margin-bottom: -2px;
      transition: color 0.15s, border-color 0.15s;
      display: flex;
      align-items: center;
      gap: 0.5rem;
    }

    .tab-nav-item:hover {
      color: #495057;
    }

    .tab-nav-item.active {
      color: #3490dc;
      border-bottom-color: #3490dc;
    }

    .tab-badge {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      min-width: 1.25rem;
      height: 1.25rem;
      padding: 0 0.375rem;
      font-size: 0.7rem;
      font-weight: 700;
      line-height: 1;
      color: #856404;
      background-color: #ffc107;
      border-radius: 10rem;
    }

    .tab-badge-pending {
      background-color: #dc3545;
      color: white;
    }

    .tab-badge-translated {
      background-color: #28a745;
      color: white;
    }

    /* Batch Progress */
    .batch-progress-container {
      background-color: #e8f4fd;
      padding: 0.75rem 1rem;
      margin-bottom: 1rem;
      border-radius: 0.25rem;
      border: 1px solid #b8daff;
    }

    .batch-progress-bar-wrapper {
      background-color: #dee2e6;
      border-radius: 0.25rem;
      overflow: hidden;
      height: 0.75rem;
      margin-bottom: 0.5rem;
    }

    .batch-progress-bar {
      background-color: #3490dc;
      height: 100%;
      transition: width 0.3s ease;
      border-radius: 0.25rem;
    }

    .batch-progress-text {
      color: #004085;
      font-size: 0.8rem;
      font-weight: 500;
    }

    /* Extract Button */
    .btn-extract {
      background-color: #6f42c1;
      color: white;
      border-color: #6f42c1;
    }

    .btn-extract:hover {
      background-color: #5a32a3;
      border-color: #5a32a3;
    }

    .btn-extract:disabled {
      background-color: #6f42c1;
      opacity: 0.65;
      cursor: not-allowed;
    }

    /* LLM Override */
    .llm-override-card {
      border-left: 3px solid #3490dc;
      padding: 0.75rem 1rem;
      margin-bottom: 1rem;
      background-color: #f8f9fa;
      border-radius: 0 0.25rem 0.25rem 0;
    }

    .llm-override-header {
      margin-bottom: 0.5rem;
    }

    .llm-override-active {
      display: flex;
      align-items: center;
      gap: 0.75rem;
      padding: 0.5rem 0.75rem;
      margin-bottom: 0.75rem;
      background-color: #d4edda;
      border: 1px solid #c3e6cb;
      border-radius: 0.25rem;
      font-size: 0.875rem;
    }

    .llm-override-active-label {
      font-weight: 600;
      color: #155724;
    }

    .llm-override-active-value {
      color: #155724;
    }

    .llm-override-form {
      display: flex;
      flex-direction: column;
      gap: 0.75rem;
    }

    .form-row {
      display: flex;
      gap: 1rem;
    }

    .form-select {
      appearance: auto;
    }

    /* Batch Translate Button */
    .btn-warning {
      background-color: #ffc107;
      color: #212529;
      border-color: #ffc107;
    }

    .btn-warning:hover {
      background-color: #e0a800;
      border-color: #d39e00;
    }

    .btn-warning:disabled {
      background-color: #ffc107;
      opacity: 0.65;
      cursor: not-allowed;
    }
    """
  end
end
